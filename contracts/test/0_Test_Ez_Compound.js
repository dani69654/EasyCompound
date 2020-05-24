const Easy_Compound = artifacts.require('Easy_Compound');
const truffleAssert = require ("truffle-assertions");
const Web3 = require('web3');

//Importing contracts ABIs
const abi_Easy_Compound = require('../test/abis/abi_Easy_Compound.js');
const abi_Dai_Contract = require('../test/abis/abi_Dai_Contract.js');
const abi_cDai_Contract = require('../test/abis/abi_cDai_Contract.js');
const abi_cEth_Contract = require('../test/abis/abi_cEth_Contract.js');



//Declaring contract addresses

const cEthContractAddress = '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5';
const daiContractAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const cDaiContractAddress = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643";


//Instancing web3 interfaces
const compoundCEthContract = new web3.eth.Contract(abi_cEth_Contract, cEthContractAddress);
const compoundDaiContract = new web3.eth.Contract(abi_Dai_Contract, daiContractAddress);
const compoundcDaiContract = new web3.eth.Contract(abi_cDai_Contract, cDaiContractAddress);




contract("Easy_Compound", async function(accounts){


let instance;
let contractInstance;
const oneToken = Web3.utils.toWei('1', 'ether');
const almostOneToken = Web3.utils.toWei('0.999', 'ether');


const web3 = new Web3('http://127.0.0.1:8545');


  before (async function(){
    instance = await Easy_Compound.new(daiContractAddress,cDaiContractAddress,cEthContractAddress);
    contractInstance = new web3.eth.Contract(abi_Easy_Compound, instance.address, {from: accounts[0]});
    console.log('Setup Done');
  })





  it("Should deposit Ether.", async function (){

    //Depositing Ether
    await contractInstance.methods.depositEther().send({from: accounts[0],value:oneToken});

    //Checking Ether balance
    let result = await contractInstance.methods.getUserEthBalance(accounts[0]).call();

    //Asserts user Ether balance == 1 Ether
    assert (result == oneToken);

  })


  it("Should move dai from user to Dai escrow.", async function(){

    //Granting allowance to smart contract to grab money from accounts[0];
    await compoundDaiContract.methods.approve(instance.address, oneToken).send({from:accounts[0]});

    //Moving the authorized Dai amount from user to escrow
    await contractInstance.methods.depositDaiTokens(oneToken).send({from:accounts[0]});

    //Returns dai balance in escrow. Since that was the only Dai deposit, must be oneToken
    let result = await contractInstance.methods.getDaiBalance().call();
    assert (result == oneToken);

  })


  it("Should supply Ether to Compound.", async function(){

    //Depositing Ether in exchange of cEth
    await contractInstance.methods.supplyEthToCompound(oneToken).send({from: accounts[0],
    gasLimit: web3.utils.toHex(1500000),
    gasPrice: web3.utils.toHex(200000000000)});


    //Checking cEth accounts[0] balance
    let result = await contractInstance.methods.getUserCethBalance(accounts[0]).call();
    console.log("User has: " + result.toString() + " cEth");

    //Checking cEth in contract by using the cToken abstaction
    let result1 = await contractInstance.methods.getCEthBalance().call();
    console.log("Contract has: " +result.toString() + " cEth");

    //Checking cEth in contract by using the contract variable
    let result2 = await contractInstance.methods.getContractCethBalance().call();
    console.log("Contract has: " +result.toString() + " cEth");

    //The 3 results obtained should be the same since all the balances were 0
    assert(result == result1 &&  result1 == result2);

    //User should have 0 Ether because they were just swapped into cEth
    result = await contractInstance.methods.getUserEthBalance(accounts[0]).call();
    assert(result == 0);

  })


  it("Should redeem cEth.", async function(){

    //Redeeming all the cEth tokens we deposited before
    let userToken = await contractInstance.methods.getCEthBalance().call();
    let check = await contractInstance.methods.redeemCtokens(userToken,cEthContractAddress).send({from: accounts[0],
    gasLimit: web3.utils.toHex(1500000),
    gasPrice: web3.utils.toHex(200000000000)});

    //Asserts accounts[0] has now 0 cEth
    let result = await contractInstance.methods.getUserCethBalance(accounts[0]).call();
    assert(result == 0);

    //Asserts  contract has now 0 cEth
    result = await contractInstance.methods.getContractCethBalance().call();
    assert(result == 0);

    //Assertes accounts[0] has ≃ 1 Ether, will not be one because of fees
    result = await contractInstance.methods.getUserEthBalance(accounts[0]).call();
    assert(result > almostOneToken);
  })


  it("Should supply Dai to Compound.", async function(){


    //Depositing all user Dai in exchange of cDAI and swapping them in cDai
    await contractInstance.methods.getUserDaiBalance(accounts[0]).call().then(async function(res){
      await contractInstance.methods.supplyErc20ToCompound(res).send({
        from: accounts[0],
        gasLimit: web3.utils.toHex(1500000),
        gasPrice: web3.utils.toHex(200000000000)
      })
    })

    //Asserts contract's Dai balance == 0
    let result = await contractInstance.methods.getDaiBalance().call();
    assert(result == 0);
    result = await contractInstance.methods.getContractDaiBalance().call();
    assert(result == 0);

    //Asserts user Dai balance == 0
    result = await contractInstance.methods.getUserDaiBalance(accounts[0]).call();
    assert(result == 0);

    //Asserting user and contract got credited cDAI
    let userCdaiBalance = await contractInstance.methods.getUserCdaiBalance(accounts[0]).call();
    let contractCdaiBalance = await contractInstance.methods.getUserCdaiBalance(accounts[0]).call();

  })


  it("should redeem cDai to Dai: ", async function(){

    //Asserting user has no Dai
    let result = await contractInstance.methods.getUserDaiBalance(accounts[0]).call();
    assert (result == 0);

    //Redeeming cDai for Dai
    let userToken = await contractInstance.methods.getUserCdaiBalance(accounts[0]).call();
    let check = await contractInstance.methods.redeemCtokens(userToken,cDaiContractAddress).send({from: accounts[0],
    gasLimit: web3.utils.toHex(1500000),
    gasPrice: web3.utils.toHex(200000000000)});

    //Asserting user got Dai back
    let userDaibalance = await contractInstance.methods.getUserDaiBalance(accounts[0]).call();
    assert (userDaibalance >= oneToken); //Will be a bit more than one Dai thanks to fees

    //Asserting user and contract balances are the same
    let contractDaibalance = await contractInstance.methods.getDaiBalance().call();
    assert (userDaibalance == contractDaibalance);

  })

})
