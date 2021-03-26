// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../cvaults/bsc/CVaultBSCFlipStorage.sol";

interface IDashboard {
    function cVaultBSCFlipStorage() external view returns(CVaultBSCFlipStorage);
    function relayerBSC() external view returns(ICVaultRelayer);
    function priceOfBNB() external view returns (uint);

    function valueOfAsset(address asset, uint amount) external view returns(uint, uint);
}