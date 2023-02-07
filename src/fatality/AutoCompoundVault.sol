// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IBunnyMinter {
    function performanceFee(uint256 profit) external view returns (uint256);
    function mintForV2(address asset, uint256 _performanceFee, address to) external;
}

/// @dev Auto-compounding vault where there is an exit tax on withdrawal of LP tokens:
/// @dev Specifically, withdrawing LP tokens results in 1% being converted to BUNNY which
/// @dev is sent to the user and 99% of the LP tokens is returned directly to the user
/// @dev All LP tokens must be withdrawn by user in order to receive earned fees
/// auto-compounding logic is not included here, irrelevant to the exploit - 
/// this will just mean that user has earned no fees at the time of withdrawal
contract AutoCompoundVault is Ownable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 internal _stakingToken;
    IBunnyMinter internal _minter;

    uint256 public totalShares;
    mapping (address => uint256) private _shares;

    uint256 private constant DUST = 1000;

    // auto-compounding state variables ...

    constructor(address _stakingTokenAddress, address _minterAddress) {
        _stakingToken = IERC20(_stakingTokenAddress);
        _stakingToken.approve(_minterAddress,type(uint256).max);
        _minter = IBunnyMinter(_minterAddress);
    }

    /// @dev Allows user to deposit entire amount of `_stakingToken`
    function depositAll() external {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    /// @dev User withdraws all staked LP tokens (including rewards) & pays associated fees
    /// auto-compounding not implemented here so there will be no rewards
    function withdrawAllAndEarn() external {
        uint256 amount = balanceOf(msg.sender);
        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint256 profit = amount; // fee calculated on entire staked amount
        uint256 performanceFee = _minter.performanceFee(profit); // fee is 1% of LP tokens

        if (performanceFee > DUST) {
            _minter.mintForV2(
                address(_stakingToken), 
                performanceFee, 
                msg.sender
            );
            amount = amount.sub(performanceFee);
        }

        _stakingToken.safeTransfer(msg.sender, amount); // return 99% of LP tokens to user
    }

    /// @dev Return the total supply of shares issued
    function totalSupply() external view returns (uint256) {
        return totalShares;
    }

    /// @dev User deposits specific amount of `_stakingToken`
    function deposit(uint256 _amount) public {
        _depositTo(_amount, msg.sender);
    }

    /// @dev Returns balance of underlying `_stakingToken` for `account` based on shares
    function balanceOf(address account) public view returns (uint256) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    /// @dev Gets total balance of `_stakingToken` deposited into this contract
    /// normally this would get the balance of the LP deposited in MasterChef - 
    /// however this is not done here bc auto-compounding logic is removed
    function balance() public view returns (uint256 amount) {
        amount = _stakingToken.balanceOf(address(this));
    }

    /// @dev Returns the number of shares for `account`
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    /// @dev Allows user to deposit LP tokens & issues equivalent shares
    function _depositTo(uint256 _amount, address _to) private {
        uint256 _pool = balance();

        uint256 _before = _stakingToken.balanceOf(address(this));
        _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = _stakingToken.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens

        uint256 shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalShares)).div(_pool);
        }

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);
    }

    // auto-compounding logic ...

}