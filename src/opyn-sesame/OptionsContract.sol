// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./OptionsLogic.sol";


interface IMarketplace {
    function deposit(address sender, uint256 amount) external;
}

/// @dev Allows only ETH-USDC put options, where USDC is the collateral
/// @dev Option allows user to sell ETH at a specified USDC strike price
/// @dev Options must be fully collateralized with USDC, no liquidation risk
/// @dev Options are American so windowSize is irrelevant for exercise
contract OptionsContract is OptionsLogic {

    IMarketplace marketplace; // for selling oTokens

    /**
    * @dev The underlying asset will always be ETH
    * @dev Collateral and strike are always USDC
    * @dev Precision for all assets & conversions is fixed to 1e18
    */
    constructor(
        IERC20 _usdc, // used as collateral & strike
        uint256 _strikePrice, // amount USDC you can sell 1 ETH for
        uint256 _expiry, // when option expires
        address _marketplace // where oTokens are sold for premium
    ) OptionsLogic(
        _usdc, // collateral
        _strikePrice,
        _usdc, // strike
        _expiry
    ) {
        marketplace = IMarketplace(_marketplace);
    }

    /// @dev Opens a vault, adds USDC collateral, mints new oTokens, and sells oTokens
    function createAndSellERC20CollateralOption(
        uint256 amtCollateral
    ) external {
        openVault(); // opens vault for msg.sender
        addERC20Collateral(amtCollateral); // post collateral for msg.sender, mints oTokens
        uint256 balance = balanceOf(msg.sender); // get amount of oTokens minted
        approve(address(marketplace),balance); // approve for msg.sender
        marketplace.deposit(msg.sender,balance);
    }

}