// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IBunnyPool {

    function balanceOf(address account) external view returns (uint);
    function earned(address account) external view returns (uint[] memory);
    function rewardTokens() external view returns (address [] memory);

    function deposit(uint _amount) external;
    function withdraw(uint _amount) external;
    function withdrawAll() external;
    function getReward() external;

    function depositOnBehalf(uint _amount, address _to) external;
    function notifyRewardAmounts(uint[] memory amounts) external;
}