// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVenusDistribution {
    function enterMarkets(address[] memory _vtokens) external;
    function exitMarket(address _vtoken) external;
    function getAssetsIn(address account) external view returns (address[] memory);

    function markets(address vTokenAddress) external view returns (bool, uint, bool);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);

    function claimVenus(address holder) external;
    function venusSpeeds(address) external view returns (uint);
}
