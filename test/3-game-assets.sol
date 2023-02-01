// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {GameAsset} from "src/game-assets/GameAsset.sol";
import {AssetWrapper} from "src/game-assets/AssetWrapper.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    AssetWrapper assetWrapper;
    GameAsset swordAsset;
    GameAsset shieldAsset;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying core contracts
        vm.prank(admin);
        assetWrapper = new AssetWrapper('');

        vm.prank(admin);
        swordAsset = new GameAsset('SWORD','SWORD');
        vm.prank(admin);
        shieldAsset = new GameAsset('SHIELD','SHIELD');

        // whitelist the two assets for use in the game
        vm.prank(admin);
        assetWrapper.updateWhitelist(address(swordAsset));
        vm.prank(admin);
        assetWrapper.updateWhitelist(address(shieldAsset));

        // set operator of the two game assets to be the wrapper contract
        vm.prank(admin);
        swordAsset.setOperator(address(assetWrapper));
        vm.prank(admin);
        shieldAsset.setOperator(address(assetWrapper));

        // adminUser is the user you will be griefing
        // minting 1 SWORD & 1 SHIELD asset for adminUser
        vm.prank(admin);
        swordAsset.mintForUser(adminUser,1);
        vm.prank(admin);
        shieldAsset.mintForUser(adminUser,1);

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

        // attacker traps user's SWORD and SHIELD NFTs inside assetWrapper contract
        assertEq(swordAsset.balanceOf(adminUser),0);
        assertEq(shieldAsset.balanceOf(adminUser),0);

        assertEq(swordAsset.balanceOf(address(assetWrapper)),1);
        assertEq(shieldAsset.balanceOf(address(assetWrapper)),1);

        assertEq(assetWrapper.balanceOf(adminUser,0),0);
        assertEq(assetWrapper.balanceOf(adminUser,1),0);

    }

}