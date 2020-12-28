// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../vaults/VaultController.sol";


contract VaultControllerTester is VaultController {
    function initialize(address _token) external initializer {
        __VaultController_init(IBEP20(_token));
        setMinter(IBunnyMinter(0x0B4A714AAf59E46cb1900E3C031017Fd72667EfE));
    }
}
