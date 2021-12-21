// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;


/*
      ___       ___       ___       ___       ___
     /\  \     /\__\     /\  \     /\  \     /\  \
    /::\  \   /:/ _/_   /::\  \   _\:\  \    \:\  \
    \:\:\__\ /:/_/\__\ /::\:\__\ /\/::\__\   /::\__\
     \::/  / \:\/:/  / \:\::/  / \::/\/__/  /:/\/__/
     /:/  /   \::/  /   \::/  /   \:\__\    \/__/
     \/__/     \/__/     \/__/     \/__/

*
* MIT License
* ===========
*
* Copyright (c) 2021 QubitFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/


interface IQMultiplexer{
    // position management
    function createPosition(address pool, uint[] memory depositAmount, uint[] memory borrowAmount) external payable;
    function closePosition(address pool, uint id) external;
    function increasePosition(address pool, uint id, uint[] memory depositAmount, uint[] memory borrowAmount) external payable;
    function reducePosition(address lpToken, uint id, uint reduceAmount, uint[] memory repayAmount) external;
    function getReward(address pool, uint id) external;
    function liquidationRefund(address pool, uint id) external;

    // events
    event OpenPosition(address indexed account, address indexed pool, uint id);
    event ClosePosition(address indexed account, address indexed pool, uint id);
    event KillPosition(address indexed pool, uint id, uint token0Incentive, uint token1Incentive);

    event Deposited(address indexed account, address indexed pool, uint id, uint token0Amount, uint token1Amount, uint lpAmount);
    event Withdrawn(address indexed account, address indexed pool, uint id, uint withdrawnAmount, uint token0Refund, uint token1Refund);
    event Borrow(address indexed account, address indexed pool, uint id, uint token0Borrow, uint token1Borrow);
    event Repay(address indexed account, address indexed pool, uint id, uint token0Repay, uint token1Repay);

    event ClaimReward(address indexed account, address indexed pool, uint id, uint reward);
    event Harvested(address indexed pool, uint harvested);
    event PerformanceFee(address indexed pool, uint performanceFee);
}