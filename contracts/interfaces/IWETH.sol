// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IWETH {
    function approve(address spender, uint value) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);

    function deposit() external payable;
    function withdraw(uint amount) external;
}
