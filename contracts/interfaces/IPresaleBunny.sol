// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IPresaleBunny {
    function flipToken() view external returns(address);
    function users(uint index) external view returns(address);
    function balanceOf(address account) view external returns(uint);
    function totalBalance() view external returns(uint);

    function setMasterChef(address _masterChef) external;
    function setStakingRewards(address _rewards) external;
    function distributeTokens(uint index, uint length, uint _pid) external;
    function finalize() external;
}