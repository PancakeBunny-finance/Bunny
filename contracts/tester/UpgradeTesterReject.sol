// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/PausableUpgradeable.sol";


contract UpgradeTesterReject is PausableUpgradeable {

    // 1. deploy proxy with hardhat
    // 2. proxyAdmin to Timelock
    // 3. prepareUpgrade with hardhat
    // 4. queueTransaction to upgradeProxy with Timelock
    // 5. advance evm time
    // 6. executeTransaction to upgradePoxy with Timelock
    // 7. check value updated

    /* ========== STATE VARIABLES ========== */

    bool public reject;
    uint public version;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __PausableUpgradeable_init();
        reject = true;
        version = 3;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setVersion(uint _version) external onlyOwner {
        version = _version;
    }
}
