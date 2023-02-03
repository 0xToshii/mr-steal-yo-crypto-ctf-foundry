// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IFlashCallback {
    function flashCallback(
        uint256 fee,
        bytes calldata data
    ) external;
}

/// @dev Contract takes in user funds & exposes flashloan functionality to earn yield
contract FlashLoaner is ERC4626, Ownable {

    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 constant public feeMax = 10_000; // basis points
    uint256 public feeBasis = 100; // 1% as default

    event Flash(address indexed caller, address recipient, uint256 amount, uint256 paid);

    constructor(
        address _asset, 
        string memory name, 
        string memory symbol
    ) ERC4626(IERC20Metadata(_asset)) ERC20(name, symbol) {}

    /// @dev Change the fee for flashloan
    function setFee(uint256 fee) external onlyOwner {
        require(fee < feeMax,'invalid fee');
        feeBasis = fee;
    }

    /// @dev Function to perform flashloan
    function flash(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external {
        require(totalAssets() > 0, 'zero-liquidity');
        require(amount > 0, 'invalid-amount');
        
        uint256 fee = amount.mulDiv(feeBasis, feeMax, Math.Rounding.Up);
        uint256 balanceBefore = totalAssets();

        IERC20(asset()).safeTransfer(recipient, amount); // optimistic transfer
        
        IFlashCallback(msg.sender).flashCallback(fee, data);

        uint256 balanceAfter = totalAssets();
        require ((balanceBefore+fee) <= balanceAfter, 'insufficient-returned');

        uint256 paid = balanceAfter - balanceBefore; // shares remain same, total assets increase
        
        emit Flash(msg.sender, recipient, amount, paid);
    } 

}
