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

  address public daiContractAddress; // Contains Dai SmartContract address || 0x6B175474E89094C44Da98b954EedeAC495271d0F ||
  address public cDaiContractAddress; // Contains cDai SmartContract address || 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643 ||
  address public cEthContractAddress; // Contains eEth SmartContract address || 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5 ||

  uint256 public contractEtherBalance; // Total amount of Ether in Escrow
  uint256 public contractDaiBalance; // Total amount of Dai in Escrow
  uint256 public contractcEtherBalance; // Total amount of cEther in Escrow
  uint256 public contractcDaiBalance; // Total amount of cDai in Escrow


  event daiChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased
  event ethChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased

  constructor (address _daiContractAddress, address _cDaiContractAddress, address _cEthContractAddress) public {
    daiContractAddress = _daiContractAddress;
    cDaiContractAddress = _cDaiContractAddress;
    cEthContractAddress = _cEthContractAddress;
  }

  mapping (address => uint256) private EtherAddrBalance; // Total amount of Ether owner by address in Escrow
  mapping (address => uint256) private DaiAddrBalance; // Total amount of Dai owned by address in Escrow
  mapping (address => uint256) private cEtherAddrBalance; // Total amount of cEther owner by address in Escrow
  mapping (address => uint256) private cDaiAddrBalance;// Total amount of cDai owner by address in Escrow


  function depositEther () public payable returns (uint256) {
    // Deposit Ether in contract
    // Returns balance of msg.sender

    EtherAddrBalance[msg.sender] = EtherAddrBalance[msg.sender].add(msg.value);
    contractEtherBalance = contractEtherBalance.add(msg.value);
    emit ethChanged (msg.sender, msg.value);
    return EtherAddrBalance[msg.sender];
  }


  function depositDaiTokens (uint256 _amount) public returns (uint256) {
    /*
    @Dev --> You must approve this contract to use the function 'transferFrom'
         --> Uso cDaiContractAddress.approve(thisContractAddr, amount)
    Takes Dai from accounts[0], if check !=0 transferFrom failed
    Increases Dai balance of msg.sender
    Increases Dai balance of contract
    */
    bool check = Erc20(daiContractAddress).transferFrom(msg.sender,address(this), _amount);
    require (check == true, "Dai transfer failed");
    DaiAddrBalance[msg.sender] = DaiAddrBalance[msg.sender].add(_amount);
    contractDaiBalance = contractDaiBalance.add(_amount);
    emit daiChanged (msg.sender, _amount);
    return DaiAddrBalance[msg.sender];
  }


  /*  | Basic compound interactions |

  Swap Ether to cEth
  Checks if msg.sender has enough balance
  Decrease ether balance of msg.sender
  Increase cEther balance of msg.sender
  Returns the amount of cEth owned by msg.sender
  */


  function supplyEthToCompound (uint256 _amount) public payable whenNotPaused returns (uint256) {
    require (EtherAddrBalance[msg.sender] >= _amount, "Not enough balance");
    CEth(cEthContractAddress).mint.value(_amount).gas(20000000000)(); // No return, reverts on error
    EtherAddrBalance[msg.sender] = EtherAddrBalance[msg.sender].sub(_amount);

    uint256 cEthExchRate = CEth(cEthContractAddress).exchangeRateCurrent();
    cEtherAddrBalance[msg.sender] = cEtherAddrBalance[msg.sender].add(cEthExchRate.mul(_amount));

    contractEtherBalance = contractEtherBalance.sub(_amount);
    contractcEtherBalance = contractcEtherBalance.add(cEthExchRate.mul(_amount));

    return cEtherAddrBalance[msg.sender];
  }


  /*
  Swap Dai to cDAI
  Checks if msg.sender has enough balance
  Decrease Dai balance of msg.sender / contract
  Increase cDai balance of msg.sender / contract
  Returns the amount of cDai owned by msg.sender
  */

  function supplyErc20ToCompound (uint256 _numTokensToSupply) public whenNotPaused returns (uint256) {

    require (DaiAddrBalance [msg.sender] >= _numTokensToSupply, "Not enough balance");

    Erc20 underlying = Erc20(daiContractAddress);
    CErc20 cToken = CErc20(cDaiContractAddress);

    underlying.approve(cDaiContractAddress, _numTokensToSupply);
    // Mint cTokens
    uint256 check = cToken.mint(_numTokensToSupply);
    require (check == 0, "Mint failed");
    DaiAddrBalance[msg.sender] = DaiAddrBalance[msg.sender].sub(_numTokensToSupply);

    uint256 cDaiExchRate = CErc20(cDaiContractAddress).exchangeRateCurrent();
    cDaiAddrBalance[msg.sender] = cDaiAddrBalance[msg.sender].add(cDaiExchRate.mul(_numTokensToSupply));

    contractDaiBalance = contractDaiBalance.sub(_numTokensToSupply);
    contractcDaiBalance = contractcDaiBalance.add(cDaiExchRate.mul(_numTokensToSupply));
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
      cDaiAddrBalance[msg.sender] = cDaiAddrBalance[msg.sender].sub(_amount);
      contractcDaiBalance = contractcDaiBalance.sub(_amount);
      uint cDaiExchRate = CErc20(cDaiContractAddress).exchangeRateCurrent();
      contractDaiBalance = contractDaiBalance.add(_amount.div(cDaiExchRate));
      cDaiAddrBalance[msg.sender] = cDaiAddrBalance[msg.sender].add(_amount.div(cDaiExchRate));
      return true;
    }

    if(_cTokenAddress == cEthContractAddress){
      cEtherAddrBalance[msg.sender] = cEtherAddrBalance[msg.sender].sub(_amount);
      contractcEtherBalance = contractcEtherBalance.sub(_amount);
      uint256 cEthExchRate = CEth(cEthContractAddress).exchangeRateCurrent();
      contractcEtherBalance = contractcEtherBalance.add(_amount.div(cEthExchRate));
      cEtherAddrBalance[msg.sender] = cEtherAddrBalance[msg.sender].add(_amount.div(cEthExchRate));
      return true;
    }
    revert(); //This should never happen
  }


  function withdrawEther (uint256 _amount) public whenNotPaused {
    //Setting a min requirement of 0.01 to avoid spam
    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn

    require (_amount > 0.01 ether, "Min 0.01 ether");
    require (EtherAddrBalance[msg.sender] >=  _amount , "Not enough funds");

    EtherAddrBalance[msg.sender] = EtherAddrBalance[msg.sender].sub(_amount);

    contractEtherBalance = contractEtherBalance.sub(_amount);

    msg.sender.transfer(_amount);

    emit ethChanged (msg.sender, _amount);
  }



  function withdrawDai (uint256 _amount) public whenNotPaused {
    //No minimun Dai amount required yet. To update?
    //Updates mappingS by subtracting _amount
    //Emit the user address and amount withdrawn


    require (DaiAddrBalance[msg.sender] >= _amount, "Not enough funds");

    DaiAddrBalance[msg.sender] = DaiAddrBalance[msg.sender].sub(_amount);

    contractDaiBalance = contractDaiBalance.sub(_amount);

    bool check = Erc20(daiContractAddress).transfer(msg.sender, _amount);

    require (check == true, "Transfer failed");

    emit daiChanged (msg.sender, _amount);
  }





  //Getter and setter functions

  /*
    Return the balances of Easy_Compound:
    > cDai balance
    > Dai balance
    > CEth balance
  */

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

  function getcDaiExchangeRate () public returns (uint256){
    return CErc20(cDaiContractAddress).exchangeRateCurrent();
  }

  function getcEthExchangeRate () public returns (uint256){
    return CEth(cEthContractAddress).exchangeRateCurrent();
  }


  /* Return User balances in escrow and compound
     > Get user Ether balance in escrow
     > Get user Dai balance in escrow
     > Get user cEther balance in escrow
     > Get user cDai balance in escrow
  */

  function getUserEthBalance (address _user) public view returns (uint256){
    return EtherAddrBalance[_user];
  }

  function getUserDaiBalance (address _user) public view returns (uint256){
    return DaiAddrBalance[_user];
  }

  function getUsercEthBalance (address _user) public view returns (uint256){
    return cEtherAddrBalance[_user];
  }

  function getUsercDaiBalance (address _user) public view returns (uint256){
    return cDaiAddrBalance[_user];
  }



  /* Setters for main contracts
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
