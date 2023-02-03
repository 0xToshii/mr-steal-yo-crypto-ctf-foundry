// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


interface IUtils {
    function calcLiquidityShare(uint, address, address) external returns (uint share);
    function calcLiquidityUnits(uint, uint, uint, uint, uint) external returns (uint units);
    function calcShare(uint, uint, uint) external returns (uint share);
    function calcSwapOutput(uint, uint, uint) external returns (uint output);
}

/// @dev This contract represents a single pool for two tokens
/// @dev The BASE token (SAFU) is intended to be fixed across all pools
contract SafuPool is ERC20 {

    using SafeMath for uint256;

    address public BASE;
    address public TOKEN;
    IUtils immutable UTILS;

    uint public baseAmount;
    uint public tokenAmount;
    uint public baseAmountPooled;
    uint public tokenAmountPooled;

    event AddLiquidity(address member, uint inputBase, uint inputToken, uint unitsIssued);
    event RemoveLiquidity(address member, uint outputBase, uint outputToken, uint unitsClaimed);
    event Swapped(address tokenFrom, address tokenTo, uint inputAmount, uint outputAmount, address recipient);
    
    constructor (
        address _base, 
        address _token,
        address _utils
    ) ERC20(
        string(abi.encodePacked("SafuPoolV1-", IERC20Metadata(_token).name())),
        string(abi.encodePacked("SAFU-", IERC20Metadata(_token).name()))
    ) {
        BASE = _base;
        TOKEN = _token;
        UTILS = IUtils(_utils);
    }

    // Asset Movement

    // Add liquidity for self based on amount transfered of BASE and TOKEN
    function addLiquidity(uint256 _baseAmount, uint256 _tokenAmount) public returns (uint liquidityUnits) {
        IERC20(BASE).transferFrom(msg.sender,address(this),_baseAmount);
        IERC20(TOKEN).transferFrom(msg.sender,address(this),_tokenAmount);
        liquidityUnits = addLiquidityForMember(msg.sender);
    }

    // Add liquidity for a member
    function addLiquidityForMember(address member) public returns (uint liquidityUnits) {
        uint256 _actualInputBase = _getAddedBaseAmount();
        uint256 _actualInputToken = _getAddedTokenAmount();
        liquidityUnits = UTILS.calcLiquidityUnits(_actualInputBase, baseAmount, _actualInputToken, tokenAmount, totalSupply());
        _incrementPoolBalances(_actualInputBase, _actualInputToken);
        _mint(member, liquidityUnits);
        emit AddLiquidity(member, _actualInputBase, _actualInputToken, liquidityUnits);
    }

    // Removes all liquidity for self
    function removeAllLiquidity() public returns (uint outputBase, uint outputToken) {
        transfer(address(this),balanceOf(msg.sender)); // transfer all LP units for withdrawing liq
        return removeLiquidityForMember(msg.sender);
    } 

    // Remove Liquidity for a member
    // Requires that user sends the LP units they want to convert to this contract first
    function removeLiquidityForMember(address member) public returns (uint outputBase, uint outputToken) {
        uint units = balanceOf(address(this)); // expects transfer of LP units from user
        outputBase = UTILS.calcLiquidityShare(units, BASE, address(this));
        outputToken = UTILS.calcLiquidityShare(units, TOKEN, address(this));
        _decrementPoolBalances(outputBase, outputToken);
        _burn(address(this), units);
        IERC20(BASE).transfer(member, outputBase);
        IERC20(TOKEN).transfer(member, outputToken);
        emit RemoveLiquidity(member, outputBase, outputToken, units);
    }

    /// @dev Performs swap of tokens based on `amount`
    function swap(address toToken, uint256 amount) public returns (uint outputAmount) {
        if (toToken == BASE) {
            IERC20(TOKEN).transferFrom(msg.sender,address(this),amount);
        } else {
            IERC20(BASE).transferFrom(msg.sender,address(this),amount);
        }
        outputAmount = swapTo(toToken, msg.sender);
    }

    /// @dev Performs swap of token - assuming user has already sent contract other token
    function swapTo(address token, address member) public payable returns (uint outputAmount) {
        require((token == BASE || token == TOKEN), "Must be BASE or TOKEN");
        address _fromToken; uint _amount;
        if(token == BASE){
            _fromToken = TOKEN;
            _amount = _getAddedTokenAmount();
            outputAmount = _swapTokenToBase(_amount);
        } else {
            _fromToken = BASE;
            _amount = _getAddedBaseAmount();
            outputAmount = _swapBaseToToken(_amount);
        }
        emit Swapped(_fromToken, token, _amount, outputAmount, member);
        IERC20(token).transfer(member, outputAmount);
    }

    /// @dev Checks amount of `BASE` sent to this contract
    function _getAddedBaseAmount() internal view returns(uint256 _actual){
        uint _baseBalance = IERC20(BASE).balanceOf(address(this)); 
        if(_baseBalance > baseAmount){
            _actual = _baseBalance.sub(baseAmount);
        } else {
            _actual = 0;
        }
    }

    /// @dev Checks amount of `TOKEN` sent to this contract
    function _getAddedTokenAmount() internal view returns(uint256 _actual){
        uint _tokenBalance = IERC20(TOKEN).balanceOf(address(this)); 
        if(_tokenBalance > tokenAmount){
            _actual = _tokenBalance.sub(tokenAmount);
        } else {
            _actual = 0;
        }
    }

    function _swapBaseToToken(uint256 _x) internal returns (uint256 _y) {
        uint256 _X = baseAmount;
        uint256 _Y = tokenAmount;
        _y =  UTILS.calcSwapOutput(_x, _X, _Y);
        _setPoolAmounts(_X.add(_x), _Y.sub(_y));
    }

    function _swapTokenToBase(uint256 _x) internal returns (uint256 _y) {
        uint256 _X = tokenAmount;
        uint256 _Y = baseAmount;
        _y =  UTILS.calcSwapOutput(_x, _X, _Y);
        _setPoolAmounts(_Y.sub(_y), _X.add(_x));
    }

    // Data Model

    // Increment internal balances
    function _incrementPoolBalances(uint _baseAmount, uint _tokenAmount) internal {
        baseAmount += _baseAmount;
        tokenAmount += _tokenAmount;
        baseAmountPooled += _baseAmount;
        tokenAmountPooled += _tokenAmount; 
    }

    function _setPoolAmounts(uint256 _baseAmount, uint256 _tokenAmount) internal {
        baseAmount = _baseAmount;
        tokenAmount = _tokenAmount; 
    }

    // Decrement internal balances
    function _decrementPoolBalances(uint _baseAmount, uint _tokenAmount) internal {
        uint _removedBase = UTILS.calcShare(_baseAmount, baseAmount, baseAmountPooled);
        uint _removedToken = UTILS.calcShare(_tokenAmount, tokenAmount, tokenAmountPooled);
        baseAmountPooled = baseAmountPooled.sub(_removedBase);
        tokenAmountPooled = tokenAmountPooled.sub(_removedToken); 
        baseAmount = baseAmount.sub(_baseAmount);
        tokenAmount = tokenAmount.sub(_tokenAmount); 
    }

}