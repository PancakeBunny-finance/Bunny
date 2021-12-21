// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

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


interface IQPositionManager {
    // Pool Info
    struct PoolInfo {
        uint pid;
        uint lastPositionID;
        uint totalPositionShare;
        uint debtRatioLimit; // debtRatioLimit of pool
        mapping(address => uint) totalDebtShares;   // token -> debtShare
        mapping(uint => PositionInfo) positions;
    }

    // Position Info
    struct PositionInfo {
        bool isLiquidated;
        address positionOwner;
        uint principal;
        uint positionShare;
        mapping(address => uint) debtShare; // debtShare of each tokens
        mapping(address => uint) liquidateAmount;
    }

    struct UserInfo {
        mapping(address => uint) positionShare; // pool(LP) -> positionShare
        mapping(address => uint) debtShare; // token -> debtShare
        mapping (address => uint[]) positionList; // <poolAddress> => <uint array> position id list
    }

    struct PositionState {
        address account;
        bool liquidated;
        uint balance;
        uint principal;
        uint earned;
        uint debtRatio;
        uint debtToken0;
        uint debtToken1;
        uint token0Value;
        uint token1Value;
    }

    // view function
    function totalDebtValue(address token) external view returns (uint);
    function totalDebtShares(address token) external view returns (uint);

    function balance(address pool) external view returns (uint);
    function balanceOf(address pool, uint id) external view returns (uint);
    function principalOf(address pool, uint id) external view returns (uint);
    function earned(address pool, uint id) external view returns(uint);
    function debtShareOfPosition(address pool, uint id, address token) external view returns (uint);
    function debtValOfPosition(address pool, uint id) external view returns (uint[] memory);

    function pidOf(address pool) external view returns (uint);
    function getLastPositionID(address pool) external view returns (uint);
    function getPositionOwner(address pool, uint id) external view returns (address);
    function totalDebtShareOfPool(address pool, address token) external view returns (uint);

    function debtRatioOf(address pool, uint id) external view returns (uint);
    function debtRatioLimit(address pool) external view returns (uint);
    function debtShareOfUser(address account, address token) external view returns (uint);
    function debtValOfUser(address account, address token) external view returns (uint);
    function positionBalanceOfUser(address account, address pool) external view returns (uint);

    function estimateTokenValue(address lpToken, uint amount) external view returns (uint token0value, uint token1value);
    function estimateAddLiquidity(address lpToken, uint token0Amount, uint token1Amount) external view returns(uint token0Value, uint token1Value, uint token0Swap, uint token1Swap);
    function isLiquidated(address pool, uint id) external view returns (bool);
    function getLiquidationInfo(address pool, uint id) external view returns (bool, uint[] memory);
    function getBaseTokens(address lpToken) external view returns (address, address);
    function getPositionInfo(address pool, uint id) external view returns (PositionState memory);

    // state update function
    function updateDebt(address pool, uint id, address account, address token, uint borrowAmount, uint repayAmount) external;
    function updatePositionInfo(address pool, uint id, address account, uint depositAmount, uint withdrawAmount, bool updatePrincipal) external;

    // handle position state
    function pushPosition(address pool, address account, uint id) external;
    function removePosition(address pool, address account, uint id) external;
    function notifyLiquidated(address pool, uint id, uint token0Refund, uint token1Refund) external;

}
