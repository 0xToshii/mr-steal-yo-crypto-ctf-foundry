// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/// @dev Marketplace to buy/sell select oTokens
/// @dev Most logic is not implemented, but is irrelevant to exploit
contract OptionsMarket is Ownable {

    using SafeERC20 for IERC20;

    IERC20 optionsContract;
    IERC20 usdc;
    uint256 price; // fixed price for oTokens (options premium), in USDC

    // ... state variables to help w/ crediting sellers w/ gains from sales

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    /// @dev Allows setting the price in USDC for each oToken - fixed premium
    /// @dev price = 10 means 10e18 USDC per 1e18 oTokens
    function setPrice(uint256 _price) external onlyOwner {
        require(price == 0,'invalid-price');
        price = _price;
    }

    /// @dev Allows setting the address of options contract for this marketplace
    function setOptionsContract(address _optionsContract) external onlyOwner {
        require(address(optionsContract) == address(0),'invalid-contract');
        optionsContract = IERC20(_optionsContract);
    }

    /// @dev Allows options contract to sell oTokens on seller's behalf
    function deposit(address sender, uint256 amount) external {
        require(msg.sender == address(optionsContract),'invalid-depositor');
        optionsContract.safeTransferFrom(sender,address(this),amount);
        // ... some logic to credit seller for their oToken deposit
    }

    /// @dev Allows options buyers to purchase oTokens for set USDC price
    function purchase(uint256 amount) external {
        require(amount <= optionsContract.balanceOf(address(this)),'invalid-amount');
        usdc.safeTransferFrom(msg.sender,address(this),amount*price);
        optionsContract.safeTransfer(msg.sender,amount);
    }

    // ... logic to allow sellers to get the funds credited to them for selling oTokens

}