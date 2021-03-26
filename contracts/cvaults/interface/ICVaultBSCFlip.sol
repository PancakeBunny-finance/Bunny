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
*/

import "./IBankBNB.sol";
import "./IBankETH.sol";


interface ICVaultBSCFlip {
    function getUtilizationInfo() external view returns(uint liquidity, uint utilized);
    function bankBNB() external view returns(IBankBNB);
    function bankETH() external view returns(IBankETH);

    function deposit(address lp, address account, uint128 eventId, uint112 nonce, uint128 leverage, uint collateral) external returns (uint bscBNBDebtShare, uint bscFlipBalance);
    function updateLeverage(address lp, address account, uint128 eventId, uint112 nonce, uint128 leverage, uint collateral) external returns (uint bscBNBDebtShare, uint bscFlipBalance);
    function withdrawAll(address lp, address account, uint128 eventId, uint112 nonce) external returns (uint ethProfit, uint ethLoss);
    function emergencyExit(address lp, address account, uint128 eventId, uint112 nonce) external returns (uint ethProfit, uint ethLoss);
    function liquidate(address lp, address account, uint128 eventId, uint112 nonce) external returns (uint ethProfit, uint ethLoss);
}
