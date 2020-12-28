// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../library/Whitelist.sol";

contract WhitelistTester is Whitelist {
    uint public count;
    function initialize() external initializer {
        __Whitelist_init();
    }

    function increase() external onlyWhitelisted {
        count++;
    }
}
