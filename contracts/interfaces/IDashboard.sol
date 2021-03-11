// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IDashboard {
    function bankBNBAddress() external view returns(address);
    function bscFlipAddress() external view returns(address);
    function relayerAddress() external view returns(address);
    function priceOfBNB() external view returns (uint);

    function valueOfAsset(address asset, uint amount) external view returns(uint, uint);
}