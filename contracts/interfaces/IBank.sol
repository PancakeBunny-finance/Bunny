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


interface IBank {
    function pendingDebtOf(address pool, address account) external view returns (uint);
    function pendingDebtOfBridge() external view returns (uint);
    function sharesOf(address pool, address account) external view returns (uint);
    function debtToProviders() external view returns (uint);
    function getUtilizationInfo() external view returns (uint liquidity, uint utilized);

    function shareToAmount(uint share) external view returns (uint);
    function amountToShare(uint share) external view returns (uint);

    function accruedDebtOf(address pool, address account) external returns (uint debt);
    function accruedDebtOfBridge() external returns (uint debt);
    function executeAccrue() external;

    function borrow(address pool, address account, uint amount) external returns (uint debtInBNB);
//    function repayPartial(address pool, address account) external payable;
    function repayAll(address pool, address account) external payable returns (uint profitInETH, uint lossInETH);
    function repayBridge() external payable;

    function bridgeETH(address to, uint amount) external;
}

interface IBankBridge {
    function realizeProfit() external payable returns (uint profitInETH);
    function realizeLoss(uint debt) external returns (uint lossInETH);
}

interface IBankConfig {
    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);

    /// @dev Return the bps rate for reserve pool.
    function getReservePoolBps() external view returns (uint256);
}

interface InterestModel {
    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
}
