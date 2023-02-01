// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {TastyStaking} from "src/tasty-stake/TastyStaking.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    Token steak;
    Token butter;
    TastyStaking tastyStaking;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploy token contracts
        vm.prank(admin);
        steak = new Token('STEAK','STEAK'); // staking token

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=adminUser; addresses[1]=attacker;
        amounts[0]=100_000e18; amounts[1]=1e18;
        vm.prank(admin);
        steak.mintPerUser(addresses, amounts);

        vm.prank(admin);
        butter = new Token('BUTTER','BUTTER'); // reward token

        vm.prank(admin);
        butter.mint(admin, 10_000e18);

        // deploying core contracts
        vm.prank(admin);
        tastyStaking = new TastyStaking(address(steak),admin);

        // --setting up the rewards for tastyStaking
        vm.prank(admin);
        tastyStaking.addReward(address(butter));
        vm.prank(admin);
        butter.approve(address(tastyStaking),10_000e18);
        vm.prank(admin);
        tastyStaking.notifyRewardAmount(address(butter),10_000e18);

        // --other user stakes initial amount of steak
        vm.prank(adminUser);
        steak.approve(address(tastyStaking),type(uint).max);
        vm.prank(adminUser);
        tastyStaking.stakeAll();

        // advance time by an hour
        vm.warp(block.timestamp+3600);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);
        
        // implement solution here

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains all staking tokens from tastyStaking contract
        assertEq(steak.balanceOf(address(tastyStaking)),0);
        assertGt(steak.balanceOf(attacker),100_000e18);

    }

}