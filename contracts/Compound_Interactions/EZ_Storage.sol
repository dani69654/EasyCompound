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
import "./EZ_Storage.sol";
import "../Safe/Ownable.sol";
import "../Safe/SafeMath.sol";
import "../Safe/Pausable.sol";

contract EZstorage is Ownable, Pausable{

  address internal daiContractAddress; // Contains Dai SmartContract address || 0x6B175474E89094C44Da98b954EedeAC495271d0F ||
  address internal cDaiContractAddress; // Contains cDai SmartContract address || 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643 ||
  address internal cEthContractAddress; // Contains eEth SmartContract address || 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5 ||

  uint256 public contractEtherBalance; // Total amount of Ether in Escrow
  uint256 public contractDaiBalance; // Total amount of Dai in Escrow
  uint256 public contractCethBalance; // Total amount of cEther in Escrow
  uint256 public contractCdaiBalance; // Total amount of cDai in Escrow

  uint256 public oneToken = 1000000000000000000; // One token 1e18


  mapping (address => uint256) public etherAddrBalance; // Total amount of Ether owner by address in contract
  mapping (address => uint256) public daiAddrBalance; // Total amount of Dai owned by address in contract
  mapping (address => uint256) public cetherAddrBalance; // Total amount of cEther owner by address in contract
  mapping (address => uint256) public cdaiAddrBalance;// Total amount of cDai owner by address in contract

  event daiChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased
  event ethChanged (address _addr, uint256 _amount); // Emit address[0] and _amount increased/decreased


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

    function getDaiContractAddress () public view returns (address) {
      return daiContractAddress;
    }

    function getcDaiContractAddress () public view returns (address) {
      return cDaiContractAddress;
    }

    function getcEthContractAddress () public view returns (address) {
      return cEthContractAddress;
    }


}
