// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../strategy/IStrategy.sol";

interface IIIIStrategy {
    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint256 _amount) external;    // BUNNY STAKING POOL ONLY
    function withdrawAll() external;
    function getReward() external;                  // BUNNY STAKING POOL ONLY
    function harvest() external;

    function token() external view returns(address);
    function balance() external view returns (uint);
    function balanceOf(address account) external view returns(uint);
    function principalOf(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // BUNNY STAKING POOL ONLY
    function profitOf(address account) external view returns (uint _usd, uint _bunny, uint _bnb);
    function tvl() external view returns (uint);    // in USD
    function apy() external view returns(uint _usd, uint _bunny, uint _bnb);

    function info(address account) external view returns(UserInfo memory);
}