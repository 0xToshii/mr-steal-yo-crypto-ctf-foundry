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
import {Token} from "src/other/Token.sol";
import {IBondingCurve,IEminenceCurrency} from "src/bonding-curve/EminenceInterfaces.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair uniPair; // DAI-USDC trading pair
    IWETH weth;
    Token usdc;
    Token dai;
    IEminenceCurrency eminenceCurrencyBase;
    IEminenceCurrency eminenceCurrency;
    IBondingCurve bancorBondingCurve;

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
        usdc.mint(admin,1_000_000e18);

        vm.prank(admin);
        dai = new Token('DAI','DAI');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=admin; addresses[1]=adminUser;
        amounts[0]=1_000_000e18; amounts[1]=200_000e18;
        vm.prank(admin);
        dai.mintPerUser(addresses,amounts);

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

        // --adding initial liquidity for DAI-USDC
        vm.prank(admin);
        usdc.approve(address(uniRouter),type(uint).max);
        vm.prank(admin);
        dai.approve(address(uniRouter),type(uint).max);

        vm.prank(admin);
        uniRouter.addLiquidity( // creates pair
            address(usdc),address(dai),
            1_000_000e18,1_000_000e18,
            0,0,
            admin,block.timestamp
        );

        uniPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(dai)));

        // deploying core contracts
        vm.prank(admin);
        bancorBondingCurve = IBondingCurve(
            deployCode("out/BancorBondingCurve.sol/BancorBondingCurve.json")
        );

        // --base DAI <-> EMN bonding curve
        vm.prank(admin);
        eminenceCurrencyBase = IEminenceCurrency(
            deployCode(
                "out/EminenceCurrencyBase.sol/EminenceCurrencyBase.json",
                abi.encode('Eminence','EMN',999000,address(dai))
            )  
        );

        // --secondary EMN <-> TOKEN bonding curve
        vm.prank(admin);
        eminenceCurrency = IEminenceCurrency(
            deployCode(
                "out/EminenceCurrency.sol/EminenceCurrency.json",
                abi.encode('eTOKEN','TOKEN',500000,address(eminenceCurrencyBase))
            )
        );

        vm.prank(admin);
        eminenceCurrencyBase.addGM(address(eminenceCurrency));

        // interacting with core contracts
        vm.prank(adminUser);
        dai.approve(address(eminenceCurrencyBase),type(uint).max);
        vm.prank(adminUser);
        eminenceCurrencyBase.approve(address(eminenceCurrency),type(uint).max);

        // --adminUser swaps all DAI to EMN, convert 1/2 EMN to TOKEN
        vm.prank(adminUser);
        eminenceCurrencyBase.buy(200_000e18,0);
        uint256 amount_ = eminenceCurrencyBase.balanceOf(adminUser) / 2;
        vm.prank(adminUser);
        eminenceCurrency.buy(amount_,0);

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

        // attacker steals at least 50k in DAI
        assertGe(dai.balanceOf(attacker),50_000e18);

    }

}