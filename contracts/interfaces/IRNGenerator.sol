// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IRNGenerator {
    function getRandomNumber(uint _potId, uint256 userProvidedSeed) external returns(bytes32 requestId);
}