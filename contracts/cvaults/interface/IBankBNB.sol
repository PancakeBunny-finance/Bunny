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

import "../../library/PoolConstant.sol";

interface IBankBNB {
    function pendingDebtValOf(address pool, address user) external view returns (uint);
    function debtShareOf(address pool, address user) external view returns (uint);
    function debtShareToVal(uint debtShare) external view returns (uint debtVal);
    function debtValToShare(uint debtVal) external view returns (uint);
    function getUtilizationInfo() external view returns(uint liquidity, uint utilized);

    function accruedDebtValOf(address pool, address user) external returns (uint);
    function borrow(address pool, address borrower, uint debtVal) external returns (uint debt);
    function repay(address pool, address borrower) external payable returns (uint debtShares);

    function handOverDebtToTreasury(address pool, address borrower) external returns (uint debtShares);
    function repayTreasuryDebt() external payable returns (uint debtShares);

    /* ========== IStrategy.sol ========== */

    function deposit(uint _amount) external payable;
    function depositAll() external;
    function withdraw(uint256 _amount) external;
    function withdrawAll() external;
    function getReward() external;
    function harvest() external;

    function totalSupply() external view returns (uint);
    function balance() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function sharesOf(address account) external view returns (uint);
    function principalOf(address account) external view returns (uint);
    function earned(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // BUNNY STAKING POOL ONLY
    function priceShare() external view returns(uint);

    /* ========== Strategy Information ========== */

    function pid() external view returns (uint);
    function poolType() external view returns (PoolConstant.PoolTypes);
    function depositedAt(address account) external view returns (uint);
    function rewardsToken() external view returns (address);

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 withdrawalFee);
    event ProfitPaid(address indexed user, uint256 profit, uint256 performanceFee);
    event BunnyPaid(address indexed user, uint256 profit, uint256 performanceFee);
    event Harvested(uint256 profit);
}
