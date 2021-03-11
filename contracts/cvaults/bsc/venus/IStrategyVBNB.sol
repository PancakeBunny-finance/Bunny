// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IStrategyVBNB {
    function supplyBal() external view returns (uint);
    function borrowBal() external view returns (uint);
    function wantLockedTotal() external view returns (uint);

    function harvest() external;
    function migrate(address payable to) external;
    function updateBalance() external;
    function deposit() external payable;
    function withdraw(address userAddress, uint256 wantAmt) external;
}