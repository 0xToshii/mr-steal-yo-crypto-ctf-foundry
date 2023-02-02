// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {Nft721} from "src/other/Nft721.sol";
import {BonanzaMarketplace} from "src/nft-bonanza/BonanzaMarketplace.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    Token usdc;
    Nft721 nftA;
    Nft721 nftB;
    BonanzaMarketplace bonanzaMarketplace;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying payment token & NFTs for marketplace
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        vm.prank(admin);
        usdc.mint(adminUser,100e18);

        vm.prank(admin);
        nftA = new Nft721('APES','APES');
        vm.prank(admin);
        nftB = new Nft721('ApEs','ApEs');

        // --adminUser minted NFTs from collections A & B
        vm.prank(admin);
        nftA.mintForUser(adminUser,1);
        vm.prank(admin);
        nftB.mintForUser(adminUser,1);

        // deploying the marketplace & setup
        vm.prank(admin);
        bonanzaMarketplace = new BonanzaMarketplace(50,admin,address(usdc));

        vm.prank(admin);
        bonanzaMarketplace.addToWhitelist(address(nftA));
        vm.prank(admin);
        bonanzaMarketplace.addToWhitelist(address(nftB));

        // adminUser lists NFTs on the bonanza marketplace
        vm.prank(adminUser);
        nftA.setApprovalForAll(address(bonanzaMarketplace),true);
        vm.prank(adminUser);
        nftB.setApprovalForAll(address(bonanzaMarketplace),true);

        vm.prank(adminUser);
        bonanzaMarketplace.createListing(address(nftA),0,1,100e18,0);
        vm.prank(adminUser);
        bonanzaMarketplace.createListing(address(nftB),0,1,100e18,0);

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

        // attacker steals all listed NFTs from bonanza marketplace
        assertEq(nftA.balanceOf(adminUser),0);
        assertEq(nftB.balanceOf(adminUser),0);
        assertEq(nftA.balanceOf(attacker),1);
        assertEq(nftB.balanceOf(attacker),1);

    }

}