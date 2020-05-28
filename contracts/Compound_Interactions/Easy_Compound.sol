pragma solidity ^0.6.0;


import "./EZ_Storage.sol";
import "../Safe/SafeMath.sol";


contract Easy_Compound is EZstorage {

  using SafeMath for uint256;

  constructor (address _daiContractAddress, address _cDaiContractAddress, address _cEthContractAddress) public {
    daiContractAddress = _daiContractAddress;
    cDaiContractAddress = _cDaiContractAddress;
    cEthContractAddress = _cEthContractAddress;
  }



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
         --> Use cDaiContractAddress.approve(thisContractAddr, amount)
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
  Requirements: 10 Dai min
  Checks if msg.sender has enough balance
  Decrease Dai balance of msg.sender / contract
  Increase cDai balance of msg.sender / contract
  Returns the amount of cDai owned by msg.sender
  */

  function supplyErc20ToCompound (uint256 _amount) public whenNotPaused returns (bool) {

    require (_amount >= oneToken, "Min 1 Dai");
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

  }


  function withdrawEther (uint256 _amount) public whenNotPaused {
    //Setting a min requirement of 0.01 to avoid spam
    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn

    require (_amount > 0.01 ether, "Min 0.01 Ether");
    require (etherAddrBalance[msg.sender] >=  _amount , "Not enough funds");

    etherAddrBalance[msg.sender] = etherAddrBalance[msg.sender].sub(_amount);

    contractEtherBalance = contractEtherBalance.sub(_amount);

    msg.sender.transfer(_amount);

    emit ethChanged (msg.sender, _amount);
  }



  function withdrawDai (uint256 _amount) internal whenNotPaused {

    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn

    require (daiAddrBalance[msg.sender] >= _amount, "Not enough funds");

    daiAddrBalance[msg.sender] = daiAddrBalance[msg.sender].sub(_amount);

    contractDaiBalance = contractDaiBalance.sub(_amount);

    bool check = Erc20(daiContractAddress).transfer(msg.sender, _amount);

    require (check == true, "Transfer failed");

    emit daiChanged (msg.sender, _amount);
  }


  function withdrawcDai (uint256 _amount) internal whenNotPaused {

    require (cdaiAddrBalance[msg.sender] >= _amount, "Not enough funds");

    cdaiAddrBalance[msg.sender] = cdaiAddrBalance[msg.sender].sub(_amount);
    contractCdaiBalance = contractCdaiBalance.sub(_amount);

    bool check = CErc20(cDaiContractAddress).transfer(msg.sender, _amount);

    require (check == true, "Transfer failed");

    emit cDaiChanged (msg.sender, _amount);

  }


  function withdrawcEth (uint256 _amount) internal whenNotPaused {

    require (cetherAddrBalance[msg.sender] >= _amount, "Not enough funds");

    cetherAddrBalance[msg.sender] = cetherAddrBalance[msg.sender].sub(_amount);
    contractCethBalance = contractCethBalance.sub(_amount);

    bool check = CEth(cEthContractAddress).transfer(msg.sender, _amount);

    require (check == true, "Transfer failed");

    emit cEthChanged (msg.sender, _amount);

  }




  function withdrawERC20Token (address _token, uint256 _amount) public {

    // This is used to call withdrawal functions

    require (_amount > 0, "Amount must be > 0");

    if(_token == daiContractAddress) {withdrawDai(_amount);}
    else if(_token == cDaiContractAddress) {withdrawcDai(_amount);}
    else if(_token == cEthContractAddress) {withdrawcEth(_amount);}
    else{revert("Invalid address");}

  }



  //Owner can pause / unpause
  function pause () public onlyOwner returns (bool){
    _pause();
    return true;
  }

  function unpause () public onlyOwner returns (bool){
    _unpause();
    return true;
  }



  receive() external payable { }
}
