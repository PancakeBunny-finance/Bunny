// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ICPool {
    function deposit(address to, uint amount) external;
    function withdraw(address to, uint amount) external;
    function withdrawAll(address to) external;
    function getReward(address to) external;
}
