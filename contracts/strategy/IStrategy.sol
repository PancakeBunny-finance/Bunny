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
*/

struct Profit {
    uint usd;
    uint bunny;
    uint bnb;
}

struct APY {
    uint usd;
    uint bunny;
    uint bnb;
}

struct UserInfo {
    uint balance;
    uint principal;
    uint available;
    Profit profit;
    uint poolTVL;
    APY poolAPY;
}

interface IStrategy {
    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint256 _amount) external;    // BUNNY STAKING POOL ONLY
    function withdrawAll() external;
    function getReward() external;                  // BUNNY STAKING POOL ONLY
    function harvest() external;

    function balance() external view returns (uint);
    function balanceOf(address account) external view returns(uint);
    function principalOf(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // BUNNY STAKING POOL ONLY
    function profitOf(address account) external view returns (uint _usd, uint _bunny, uint _bnb);
    function tvl() external view returns (uint);    // in USD
    function apy() external view returns(uint _usd, uint _bunny, uint _bnb);

    function info(address account) external view returns(UserInfo memory);
}