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

interface IVaultCollateral {
    function WITHDRAWAL_FEE_PERIOD() external view returns (uint);
    function WITHDRAWAL_FEE_UNIT() external view returns (uint);
    function WITHDRAWAL_FEE() external view returns (uint);

    function stakingToken() external view returns (address);
    function collateralValueMin() external view returns (uint);

    function balance() external view returns (uint);
    function availableOf(address account) external view returns (uint);
    function collateralOf(address account) external view returns (uint);
    function realizedInETH(address account) external view returns (uint);
    function depositedAt(address account) external view returns (uint);

    function addCollateral(uint amount) external;
    function addCollateralETH() external payable;
    function removeCollateral() external;

    event CollateralAdded(address indexed user, uint amount);
    event CollateralRemoved(address indexed user, uint amount, uint profitInETH);
    event CollateralUnlocked(address indexed user, uint amount, uint profitInETH, uint lossInETH);
    event Recovered(address token, uint amount);
}
