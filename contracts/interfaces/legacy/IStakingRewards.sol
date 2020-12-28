// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IStakingRewards {
    function stakeTo(uint256 amount, address _to) external;
    function notifyRewardAmount(uint256 reward) external;
}