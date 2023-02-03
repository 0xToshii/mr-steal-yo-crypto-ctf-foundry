// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MulaToken} from "src/inflationary-net-worth/MulaToken.sol";
import {MasterChef,IMuny} from "src/inflationary-net-worth/MasterChef.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    MulaToken mula;
    Token muny;
    MasterChef masterChef;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        mula = new MulaToken('MULA','MULA'); // staking token

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=adminUser; addresses[1]=attacker;
        amounts[0]=10_000e18; amounts[1]=10_000e18;
        vm.prank(admin);
        mula.mintPerUser(addresses,amounts);

        vm.prank(admin);
        muny = new Token('MUNY','MUNY'); // reward token

        // deploying core contracts
        vm.prank(admin);
        masterChef = new MasterChef(
            IMuny(address(muny)),
            admin,
            1e18,
            block.number,
            block.number
        );

        vm.prank(admin);
        muny.transferOwnership(address(masterChef));

        // start MULA staking
        vm.prank(admin);
        masterChef.add(1000,IERC20(mula),false); // init staking

        vm.prank(adminUser);
        mula.approve(address(masterChef),type(uint).max);
        vm.prank(adminUser);
        masterChef.deposit(0,10_000e18);

        // simulate staking over time
        vm.roll(120); // 120 blocks

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

        // attacker must receive all rewards in a single call to deposit
        vm.roll(block.number+1);
        vm.prank(attacker);
        masterChef.deposit(0,1);

        // attacker drains all farm emissions up to this block
        assertEq(muny.balanceOf(attacker),120e18); // 1e18 per block for 120 blocks
        assertEq(muny.balanceOf(adminUser),0);
        assertEq(muny.balanceOf(address(masterChef)),0);

    }

}