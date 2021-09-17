// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

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


interface IVaultQubitBridge {

    struct MarketInfo {
        address token;
        address qToken;
        uint available;
        uint qTokenAmount;
        uint principal;
        uint rewardsDuration;
    }

    function infoOf(address vault) external view returns (MarketInfo memory);
    function availableOf(address vault) external view returns (uint);
    function snapshotOf(address vault) external view returns (uint vaultSupply, uint vaultBorrow);
    function borrowableOf(address vault, uint collateralRatioLimit) external view returns (uint);
    function redeemableOf(address vault, uint collateralRatioLimit) external view returns (uint);
    function leverageRoundOf(address vault, uint round) external view returns (uint);
    function getBoostRatio(address vault) external view returns (uint);

    function deposit(address vault, uint amount) external payable;
    function withdraw(uint amount, address to) external;
    function harvest() external returns (uint);
    function lockup(uint _amount) external;

    function supply(uint amount) external;
    function redeemUnderlying(uint amount) external;
    function redeemAll() external;
    function borrow(uint amount) external;
    function repayBorrow(uint amount) external;

    function updateRewardsDuration(uint _rewardsDuration) external;
}
