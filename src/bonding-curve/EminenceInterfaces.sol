// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBondingCurve {
    function calculatePurchaseReturn(
        uint _supply, 
        uint _reserveBalance, 
        uint32 _reserveRatio, 
        uint _depositAmount
    ) external view returns (uint);
    function calculateSaleReturn(
        uint _supply, 
        uint _reserveBalance, 
        uint32 _reserveRatio, 
        uint _sellAmount
    ) external view returns (uint);
}

interface IEminenceCurrency is IERC20 {
    function award(address _to, uint _amount) external;
    function claim(address _from, uint _amount) external;
    function addGM(address _gm) external;
    function buy(uint _amount, uint _min) external returns (uint _bought);   
    function sell(uint _amount, uint _min) external returns (uint _bought);
}