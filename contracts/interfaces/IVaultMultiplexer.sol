// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*
  ___                      _   _
 | _ )_  _ _ _  _ _ _  _  | | | |
 | _ \ || | ' \| ' \ || | |_| |_|
 |___/\_,_|_||_|_||_\_, | (_) (_)
                    |__/

*
* MIT License
* ===========
*
* Copyright (c) 2020 BunnyFinance
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


interface IVaultMultiplexer {
    struct PositionInfo {
        address account;
        uint depositedAt;
    }

    struct UserInfo {
        uint[] positionList;
        mapping(address => uint) debtShare;
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
        uint token0Refund;
        uint token1Refund;
        uint debtRatioLimit;
        uint depositedAt;
    }

    struct VaultState {
        uint balance;
        uint tvl;
        uint debtRatioLimit;
    }

    // view function
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getPositionOwner(uint id) external view  returns (address);

    // view function
    function balance() external view returns(uint);
    function balanceOf(uint id) external view returns(uint);
    function principalOf(uint id) external view returns(uint);
    function earned(uint id) external view returns(uint);
    function debtValOfPosition(uint id) external view returns (uint[] memory);
    function debtRatioOf(uint id) external view returns (uint);

    // events
    event OpenPosition(address indexed account, uint indexed id);
    event ClosePosition(address indexed account, uint indexed id);

    event Deposited(address indexed account, uint indexed id, uint token0Amount, uint token1Amount, uint lpAmount);
    event Withdrawn(address indexed account, uint indexed id, uint amount, uint token0Amount, uint token1Amount);
    event Borrow(address indexed account, uint indexed id, uint token0Borrow, uint token1Borrow);
    event Repay(address indexed account, uint indexed id, uint token0Repay, uint token1Repay);

    event RewardAdded(address indexed token, uint reward);
    event ClaimReward(address indexed account, uint indexed id, uint reward);
}