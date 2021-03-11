// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IBankETH {
    function transferProfit() external payable returns(uint ethAmount);
    function repayOrHandOverDebt(address lp, address account, uint debt) external returns(uint ethAmount);
}
