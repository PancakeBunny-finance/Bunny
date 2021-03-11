// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IWETH {
    function deposit() external;
    function withdraw(uint amount) external;
}