// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../library/WhitelistUpgradeable.sol";

contract WhitelistTester is WhitelistUpgradeable {
    uint public count;
    function initialize() external initializer {
        __WhitelistUpgradeable_init();
    }

    function increase() external onlyWhitelisted {
        count++;
    }
}
