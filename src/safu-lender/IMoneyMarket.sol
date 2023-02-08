// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMoneyMarket {
    function _supportMarket(address asset) external returns (uint);
    function supply(address asset, uint amount) external returns (uint);
    function withdraw(address asset, uint requestedAmount) external returns (uint);
}