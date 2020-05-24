pragma solidity ^0.6.0;

abstract contract Erc20 {
  function approve(address, uint)virtual external returns (bool);
  function transfer(address, uint)virtual external returns (bool);
  function balanceOf(address owner)virtual external view returns (uint256 balance);
  function transferFrom(address sender, address recipient, uint256 amount) virtual external returns (bool);
}

abstract contract CErc20 {
  function approve(address, uint)virtual external returns (bool);
  function mint(uint)virtual external returns (uint);
  function balanceOfUnderlying(address account)virtual external returns (uint);
  function totalReserves()virtual external returns (uint);
  function transfer(address dst, uint amount) virtual external returns (bool);
  function exchangeRateCurrent() virtual external returns (uint);
}

abstract contract CEth {
  function mint()virtual external payable;
  function balanceOfUnderlying(address account)virtual external returns (uint);
  function balanceOf(address owner)virtual external view returns (uint256 balance);
  function transfer(address dst, uint256 amount)virtual external returns (bool success);
  function transferFrom(address src, address dst, uint wad)virtual external returns (bool);
  function redeem(uint redeemTokens) virtual external returns (uint);
  function exchangeRateCurrent() virtual external returns (uint);
}


import "./IERC20.sol";
import './ComptrollerInterface.sol';
import './CTokenInterface.sol';
import "../Safe/Ownable.sol";
import "../Safe/SafeMath.sol";
import "../Safe/Pausable.sol";



contract Easy_Compound is Ownable, Pausable {

  using SafeMath for uint256;

  address private daiContractAddress; // Contains Dai SmartContract address || 0x6B175474E89094C44Da98b954EedeAC495271d0F ||
  address private cDaiContractAddress; // Contains cDai SmartContract address || 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643 ||
  address private cEthContractAddress; // Contains eEth SmartContract address || 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5 ||

  uint256 private contractEtherBalance; // Total amount of Ether in Escrow
  uint256 private contractDaiBalance; // Total amount of Dai in Escrow
  uint256 private contractCethBalance; // Total amount of cEther in Escrow
  uint256 private contractCdaiBalance; // Total amount of cDai in Escrow


  event daiChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased
  event ethChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased

  constructor (address _daiContractAddress, address _cDaiContractAddress, address _cEthContractAddress) public {
    daiContractAddress = _daiContractAddress;
    cDaiContractAddress = _cDaiContractAddress;
    cEthContractAddress = _cEthContractAddress;
  }

  mapping (address => uint256) private etherAddrBalance; // Total amount of Ether owner by address in contract
  mapping (address => uint256) private daiAddrBalance; // Total amount of Dai owned by address in contract
  mapping (address => uint256) private cetherAddrBalance; // Total amount of cEther owner by address in contract
  mapping (address => uint256) private cdaiAddrBalance;// Total amount of cDai owner by address in contract


  function depositEther () public payable returns (bool){
    // Deposit Ether in contract

    etherAddrBalance[msg.sender] = etherAddrBalance[msg.sender].add(msg.value);
    contractEtherBalance = contractEtherBalance.add(msg.value);
    emit ethChanged (msg.sender, msg.value);
    return true;
  }


  function depositDaiTokens (uint256 _amount) public returns (bool) {
    /*
    @Dev --> You must approve this contract to use the function 'transferFrom'
         --> Uso cDaiContractAddress.approve(thisContractAddr, amount)
    Takes Dai from accounts[0], if check !=0 transferFrom failed
    Increases Dai balance of msg.sender
    Increases Dai balance of contract
    */
    bool check = Erc20(daiContractAddress).transferFrom(msg.sender,address(this), _amount);
    require (check == true, "Dai transfer failed");
    daiAddrBalance[msg.sender] = daiAddrBalance[msg.sender].add(_amount);
    contractDaiBalance = contractDaiBalance.add(_amount);
    emit daiChanged (msg.sender, _amount);
    return true;
  }


  /*  | Basic compound interactions |

  Swap Ether to cEth
  Checks if msg.sender has enough balance
  Decrease ether balance of msg.sender
  Increase cEther balance of msg.sender
  Returns the amount of cEth owned by msg.sender
  */


  function supplyEthToCompound (uint256 _amount) public payable whenNotPaused returns (bool){

    //Check requirement and mint
    require (etherAddrBalance[msg.sender] >= _amount, "Not enough balance");
    CEth(cEthContractAddress).mint.value(_amount).gas(20000000000)(); // No return, reverts on error

    //Subtract Ether _amount from contract and user balances
    etherAddrBalance[msg.sender] = etherAddrBalance[msg.sender].sub(_amount);
    contractEtherBalance = contractEtherBalance.sub(_amount);

    //Increase Ether _amount in contract and user balances

    uint256 cEthExchRate = getCethExchangeRate();
    cetherAddrBalance[msg.sender] = cetherAddrBalance[msg.sender].add((_amount.mul(1000000000000000000)).div(cEthExchRate));
    contractCethBalance = contractCethBalance.add(cetherAddrBalance[msg.sender]);

    return true;
  }


  /*
  Swap Dai to cDAI
  Checks if msg.sender has enough balance
  Decrease Dai balance of msg.sender / contract
  Increase cDai balance of msg.sender / contract
  Returns the amount of cDai owned by msg.sender
  */

  function supplyErc20ToCompound (uint256 _amount) public whenNotPaused returns (bool) {

    require (daiAddrBalance [msg.sender] >= _amount, "Not enough balance");

    Erc20 underlying = Erc20(daiContractAddress);
    CErc20 cToken = CErc20(cDaiContractAddress);

    underlying.approve(cDaiContractAddress, _amount);

    uint256 check = cToken.mint(_amount);
    require (check == 0, "Mint failed");

    //Decreasing contract and user Dai balances -= _amount
    daiAddrBalance[msg.sender] = daiAddrBalance[msg.sender].sub(_amount);
    contractDaiBalance = contractDaiBalance.sub(_amount);

    //Increasing contract and user cDai balances += _amount
    uint256 cDaiExchRate = CErc20(cDaiContractAddress).exchangeRateCurrent();
    cdaiAddrBalance[msg.sender] = cdaiAddrBalance[msg.sender].add((_amount.mul(1000000000000000000)).div(cDaiExchRate));


    contractCdaiBalance = contractCdaiBalance.add((_amount.mul(1000000000000000000)).div(cDaiExchRate));

    return true;
  }


  /*
   Redeems a C token (both cDai and cEth)
   Based on '_cTokenAddress' will decrease/increase the correct balances
   Returns total amount of Eth / Dai redeemed
  */

  function redeemCtokens (uint _amount, address _cTokenAddress) public whenNotPaused returns (bool) {
    require (_cTokenAddress == cDaiContractAddress || _cTokenAddress == cEthContractAddress, "Cannot redeem this token");
    uint256 check = CEth(_cTokenAddress).redeem(_amount);
    require(check == 0, "Redeem failed");

    if(_cTokenAddress == cDaiContractAddress){
      cdaiAddrBalance[msg.sender] = cdaiAddrBalance[msg.sender].sub(_amount);
      contractCdaiBalance = contractCdaiBalance.sub(_amount);

      uint cDaiExchRate = CErc20(cDaiContractAddress).exchangeRateCurrent();

      contractDaiBalance = contractDaiBalance.add((_amount.mul(cDaiExchRate)).div(1000000000000000000));
      daiAddrBalance[msg.sender] = daiAddrBalance[msg.sender].add((_amount.mul(cDaiExchRate)).div(1000000000000000000));
      return true;
    }

    if(_cTokenAddress == cEthContractAddress){
      cetherAddrBalance[msg.sender] = cetherAddrBalance[msg.sender].sub(_amount);
      contractCethBalance = contractCethBalance.sub(_amount);

      uint256 cEthExchRate = CEth(cEthContractAddress).exchangeRateCurrent();

      contractEtherBalance = contractEtherBalance.add((_amount.mul(cEthExchRate)).div(1000000000000000000));
      etherAddrBalance[msg.sender] = etherAddrBalance[msg.sender].add((_amount.mul(cEthExchRate)).div(1000000000000000000));
      return true;
    }
    revert('fatal'); //This should never happen ---> This could trigger a lockdown? Fatal error
  }


  function withdrawEther (uint256 _amount) public whenNotPaused {
    //Setting a min requirement of 0.01 to avoid spam
    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn

    require (_amount > 0.01 ether, "Min 0.01 ether");
    require (etherAddrBalance[msg.sender] >=  _amount , "Not enough funds");

    etherAddrBalance[msg.sender] = etherAddrBalance[msg.sender].sub(_amount);

    contractEtherBalance = contractEtherBalance.sub(_amount);

    msg.sender.transfer(_amount);

    emit ethChanged (msg.sender, _amount);
  }



  function withdrawDai (uint256 _amount) public whenNotPaused {
    //No minimun Dai amount required yet. To update?
    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn


    require (daiAddrBalance[msg.sender] >= _amount, "Not enough funds");

    daiAddrBalance[msg.sender] = daiAddrBalance[msg.sender].sub(_amount);

    contractDaiBalance = contractDaiBalance.sub(_amount);

    bool check = Erc20(daiContractAddress).transfer(msg.sender, _amount);

    require (check == true, "Transfer failed");

    emit daiChanged (msg.sender, _amount);
  }





  //Getter and setter functions

  /*
  Returns: the balances of Easy_Compound:
    > Ether contract balance
    > Dai balance
    > cDai balance
    > CEth balance
  */

  function getContractEtherBalance () public view returns (uint256){

    //Returns variable 'contractEtherBalance';
    return contractEtherBalance;
  }

  function getContractDaiBalance () public view returns (uint256){

    //Returns variable 'contractDaiBalance';
    return contractDaiBalance;
  }

  function getContractCethBalance () public view returns (uint256){

    //Returns variable 'contractCethBalance';
    return contractCethBalance;
  }

  function getContractCdaiBalance () public view returns (uint256){

    ////Returns variable 'contractCdaiBalance';
    return contractCdaiBalance;
  }



  function getCErc20Balance () public returns (uint256){
    return CErc20(cDaiContractAddress).balanceOfUnderlying(address(this));
  }

  function getDaiBalance () public view returns (uint256){
    return Erc20(daiContractAddress).balanceOf(address(this));
  }

  function getCEthBalance() public view returns (uint256){
    return CEth(cEthContractAddress).balanceOf(address(this));
  }

  /* Return C Tokens exchange rates */

  function getCdaiExchangeRate () public returns (uint256){
    return CErc20(cDaiContractAddress).exchangeRateCurrent();
  }

  function getCethExchangeRate () public returns (uint256){
    return CEth(cEthContractAddress).exchangeRateCurrent();
  }


  /* Return User balances in escrow
     > Get user Ether balance in escrow
     > Get user Dai balance in escrow
     > Get user cEther balance in escrow
     > Get user cDai balance in escrow
  */

  function getUserEthBalance (address _user) public view returns (uint256){
    return etherAddrBalance[_user];
  }

  function getUserDaiBalance (address _user) public view returns (uint256){
    return daiAddrBalance[_user];
  }

  function getUserCethBalance (address _user) public view returns (uint256){
    return cetherAddrBalance[_user];
  }

  function getUserCdaiBalance (address _user) public view returns (uint256){
    return cdaiAddrBalance[_user];
  }



  /* Setters for compound and erc20 contracts
  Requirements: Contract must be paused
    > Dai address
    > cDai address
    > cEth address
  */


  function setDAIcontractAddress (address _newDAIaddress) public onlyOwner whenPaused returns (address){
    daiContractAddress = _newDAIaddress;
    return daiContractAddress;
  }

  function setCDAIcontractAddress (address _newCDAIaddress) public onlyOwner whenPaused returns (address){
    cDaiContractAddress = _newCDAIaddress;
    return cDaiContractAddress;
  }

  function setCETHcontractAddress (address _newCETHaddress) public onlyOwner whenPaused returns (address){
    cEthContractAddress = _newCETHaddress;
    return cEthContractAddress;
  }



  receive() external payable { }
}
