// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IBankBNB {
    function debtValOf(address pool, address user) external view returns(uint);
    function debtShareOf(address pool, address user) external view returns(uint);
    function debtShareToVal(uint debtShare) external view returns (uint debtVal);
    function debtValToShare(uint debtVal) external view returns (uint);
    function getUtilizationInfo() external view returns(uint liquidity, uint utilized);

    function accruedDebtValOf(address pool, address user) external returns(uint);
    function borrow(address pool, address borrower, uint debtVal) external returns(uint debt);
    function repay(address pool, address borrower) external payable returns(uint debtShares);

    function handOverDebtToTreasury(address pool, address borrower) external returns(uint debtShares);
    function repayTreasuryDebt() external payable returns(uint debtShares);
}
