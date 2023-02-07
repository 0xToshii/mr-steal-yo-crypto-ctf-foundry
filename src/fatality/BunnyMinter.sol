// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


interface IMinter {
    function mint(address user, uint256 amount) external;
}

interface IZapBSC {
    function zapInToken(address _from, uint256 amount, address _to) external;
}

/// @dev Handles logic for minting BUNNY to users based on provided performanceFee
/// @dev LP tokens taken as performanceFee are sent to contract owner
contract BunnyMinter is Ownable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IUniswapV2Router02 router;
    IZapBSC zapBSC;

    uint256 constant FEE_MAX = 10000;
    uint256 constant PERFORMANCE_FEE = 100;
    uint256 public bunnyPerProfitBNB = 5e18; // 5 BUNNY per BNB

    address public immutable BNB;
    address public immutable BUNNY;
    address public immutable BUNNY_BNB; // LP

    address private _minter;

    modifier onlyMinter {
        require(msg.sender == _minter);
        _;
    }

    constructor(
        address _zapBSC,
        address _router,
        address _bnb,
        address _bunny, 
        address _bunnyBNB
    ) {
        zapBSC = IZapBSC(_zapBSC);
        router = IUniswapV2Router02(_router);
        BNB = _bnb;
        BUNNY = _bunny;
        BUNNY_BNB = _bunnyBNB;
    }

    function setMinter(address _minterAddress) external onlyOwner {
        _minter = _minterAddress;
    }

    /// @dev Wrapper for converting fees to BUNNY-BNB LP and minting user BUNNY
    /// @param asset The address of the LP token used for the performance fee
    function mintForV2(
        address asset, 
        uint256 performanceFee, 
        address to
    ) external onlyMinter {
        uint feeSum = performanceFee; // the only fee
        _transferAsset(asset, feeSum);

        uint256 bunnyBNBAmount = _zapAssetsToBunnyBNB(asset, feeSum);
        if (bunnyBNBAmount == 0) return;

        IERC20(BUNNY_BNB).safeTransfer(owner(), bunnyBNBAmount); // fees (in LP) sent to owner

        uint256 valueInBNB = valueOfAsset(BUNNY_BNB, bunnyBNBAmount);

        uint256 mintBunny = amountBunnyToMint(valueInBNB);
        if (mintBunny == 0) return;
        _mint(mintBunny, to);
    }

    /// @dev Calculates amount of LP to take as a fee given `profit`
    function performanceFee(uint256 profit) public view returns (uint256) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    /// @dev Calculates amount of BUNNY to mint given BNB profit
    function amountBunnyToMint(uint256 bnbProfit) public view returns (uint256) {
        return bnbProfit.mul(bunnyPerProfitBNB).div(1e18);
    }

    /// @dev Determines the price of `asset` LP in BNB terms, per LP token
    function valueOfAsset(address asset, uint256 amount) public view returns (uint valueInBNB) {
        if (IUniswapV2Pair(asset).totalSupply() == 0) return 0;

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(asset).getReserves();
        if (IUniswapV2Pair(asset).token0() == BNB) {
            valueInBNB = amount.mul(reserve0).mul(2).div(IUniswapV2Pair(asset).totalSupply());
        } else if (IUniswapV2Pair(asset).token1() == BNB) {
            valueInBNB = amount.mul(reserve1).mul(2).div(IUniswapV2Pair(asset).totalSupply());
        } else {
            assert(false); // this LP is invalid
        }
    }

    /// @dev Zaps `asset` into BUNNY-BNB liquidity
    function _zapAssetsToBunnyBNB(
        address asset, 
        uint256 amount
    ) private returns (uint256 bunnyBNBAmount) {
        uint256 _initBunnyBNBAmount = IERC20(BUNNY_BNB).balanceOf(address(this));

        if (IERC20(asset).allowance(address(this), address(router)) == 0) {
            IERC20(asset).safeApprove(address(router), type(uint256).max);
        }

        IUniswapV2Pair pair = IUniswapV2Pair(asset);
        address token0 = pair.token0();
        address token1 = pair.token1();

        (uint256 amountToken0, uint256 amountToken1) = router.removeLiquidity(
            token0, token1, 
            amount, 
            0, 0, 
            address(this), 
            block.timestamp
        );

        if (IERC20(token0).allowance(address(this), address(zapBSC)) == 0) {
            IERC20(token0).safeApprove(address(zapBSC), type(uint256).max);
        }
        if (IERC20(token1).allowance(address(this), address(zapBSC)) == 0) {
            IERC20(token1).safeApprove(address(zapBSC), type(uint256).max);
        }

        zapBSC.zapInToken(token0, amountToken0, BUNNY_BNB);
        zapBSC.zapInToken(token1, amountToken1, BUNNY_BNB);

        bunnyBNBAmount = IERC20(BUNNY_BNB).balanceOf(address(this)).sub(_initBunnyBNBAmount);
    }

    /// @dev Mints BUNNY for user and devs
    function _mint(uint amount, address to) private {
        IMinter tokenBUNNY = IMinter(BUNNY);

        tokenBUNNY.mint(to, amount);

        uint256 bunnyForDev = amount.mul(15).div(100);
        tokenBUNNY.mint(owner(),bunnyForDev);
    }

    /// @dev Wrapper for transfering `asset` to this contract
    function _transferAsset(address asset, uint amount) private {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

}