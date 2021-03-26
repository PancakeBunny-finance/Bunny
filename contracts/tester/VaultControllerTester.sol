// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../vaults/VaultController.sol";


contract VaultControllerTester is VaultController {
    function initialize(address _token) external initializer {
        __VaultController_init(IBEP20(_token));
        setMinter(0x8cB88701790F650F273c8BB2Cc4c5f439cd65219);
    }
}
