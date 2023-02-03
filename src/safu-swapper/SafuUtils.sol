// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @dev Contract of utility functions
contract SafuUtils {

    using SafeMath for uint;

    uint public constant one = 10**18;

    function calcShare(uint part, uint total, uint amount) public pure returns (uint) {
        // share = amount * part/total
        return (amount.mul(part)).div(total);
    }

    /// @dev Calculates value of LP units given balance of token in pool
    function calcLiquidityShare(uint units, address token, address pool) public view returns (uint) {
        uint amount = IERC20(token).balanceOf(pool);
        uint totalSupply = IERC20(pool).totalSupply();
        return (amount.mul(units)).div(totalSupply);
    }

    /// @dev Calculates LP units to mint for user given deposited token amounts
    function calcLiquidityUnits(uint b, uint B, uint t, uint T, uint P) public pure returns (uint) {
        if (P == 0) {
            return b;
        } else {
            // units = ((P (t B + T b))/(2 T B)) * slipAdjustment
            // P * (part1 + part2) / (part3) * slipAdjustment
            uint slipAdjustment = getSlipAdjustment(b, B, t, T);
            uint part1 = t.mul(B);
            uint part2 = T.mul(b);
            uint part3 = T.mul(B).mul(2);
            uint _units = (P.mul(part1.add(part2))).div(part3);
            return _units.mul(slipAdjustment).div(one);  // Divide by 10**18
        }
    }

    /// @dev Calculates slippage between pool tokens ratio and added tokens ratio
    function getSlipAdjustment(uint b, uint B, uint t, uint T) public pure returns (uint) {
        // slipAdjustment = (1 - ABS((B t - b T)/((2 b + B) (t + T))))
        // 1 - ABS(part1 - part2)/(part3 * part4))
        uint part1 = B.mul(t);
        uint part2 = b.mul(T);
        uint part3 = b.mul(2).add(B);
        uint part4 = t.add(T);
        uint numerator;
        if (part1 > part2){
            numerator = part1.sub(part2);
        } else {
            numerator = part2.sub(part1);
        }
        uint denominator = part3.mul(part4);
        return one.sub((numerator.mul(one)).div(denominator)); // Multiply by 10**18
    }

    /// @dev Fees are implicitly included in the calcSwapOutput equation
    /// @dev Fee equation: y = (x * x * Y) / (x + X)^2
    function calcSwapOutput(uint x, uint X, uint Y) public pure returns (uint) {
        // y = (x * X * Y )/(x + X)^2
        uint numerator = x.mul(X.mul(Y));
        uint denominator = (x.add(X)).mul(x.add(X));
        return numerator.div(denominator);
    }

}