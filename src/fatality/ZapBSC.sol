// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


/// @dev Functionality to zap LP assets into BUNNY-BNB LP tokens
contract ZapBSC is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Router02 router;

    address public immutable BNB;
    address public immutable USDC;
    address public immutable BUNNY;

    address private _minter;

    modifier onlyMinter {
        require(msg.sender == _minter);
        _;
    }

    constructor(
        address _router,
        address _bnb,
        address _usdc,
        address _bunny
    ) {
        router = IUniswapV2Router02(_router);
        BNB = _bnb;
        USDC = _usdc;
        BUNNY = _bunny;
    }

    function setMinter(address _minterAddress) external onlyOwner {
        _minter = _minterAddress;
    }

    /// @dev Allows owner to get trapped funds from this contract
    function sweep(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    /// @dev Entry for BunnyMinter to convert arbitrary tokens to BUNNY-BNB LP
    /// @param _to Address of the Uniswap LP token
    function zapInToken(address _from, uint256 amount, address _to) external onlyMinter {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        IUniswapV2Pair pair = IUniswapV2Pair(_to);
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (_from == token0 || _from == token1) { // e.g. if `_from` is BNB
            // swap half amount for other
            address other = _from == token0 ? token1 : token0;
            _approveTokenIfNeeded(other);
            uint256 sellAmount = amount.div(2);
            uint256 otherAmount = _swap(_from, sellAmount, other, address(this));
            router.addLiquidity(
                _from, other, 
                amount.sub(sellAmount), otherAmount, 
                0, 0, 
                msg.sender, 
                block.timestamp
            );
        } else { // swap `_from` to BNB, e.g. if `_from` is USDC
            uint256 bnbAmount = _swap(_from, amount, BNB, address(this)); // first swap to BNB

            address other = BNB == token0 ? token1 : token0;
            _approveTokenIfNeeded(other);
            uint256 sellAmount = bnbAmount.div(2);
            _approveTokenIfNeeded(BNB);
            uint256 otherAmount = _swap(BNB, sellAmount, other, address(this));
            router.addLiquidity(
                BNB, other, 
                bnbAmount.sub(sellAmount), otherAmount, 
                0, 0, 
                msg.sender, 
                block.timestamp
            );
        }
    }

    /// @dev Handles swapping functionality
    /// @dev Assumes that there is a Uniswap pool for `_from` and `_to`
    function _swap(
        address _from, 
        uint256 amount, 
        address _to, 
        address receiver
    ) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amount, 0, 
            path, receiver, block.timestamp
        );

        return amounts[amounts.length-1];
    }

    /// @dev Approves token for use by router
    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(router)) == 0) {
            IERC20(token).safeApprove(address(router), type(uint256).max);
        }
    }

}