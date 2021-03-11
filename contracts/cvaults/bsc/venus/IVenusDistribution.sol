// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVenusDistribution {
    function claimVenus(address holder) external;

    function enterMarkets(address[] memory _vtokens) external;

    function exitMarket(address _vtoken) external;

    function getAssetsIn(address account)
    external
    view
    returns (address[] memory);

    function getAccountLiquidity(address account)
    external
    view
    returns (
        uint256,
        uint256,
        uint256
    );

    function venusSpeeds(address) external view returns (uint);
}