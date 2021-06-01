// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IPotController {
    function numbersDrawn(uint potId, bytes32 requestId, uint256 randomness) external;
}
