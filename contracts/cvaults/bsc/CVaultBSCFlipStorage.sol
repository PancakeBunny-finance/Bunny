// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../../library/PausableUpgradeable.sol";
import "./CVaultBSCFlipState.sol";
import "../interface/ICVaultRelayer.sol";

contract CVaultBSCFlipStorage is CVaultBSCFlipState, PausableUpgradeable {
    mapping (address => Pool) private _pools;

    uint public constant LEVERAGE_MAX = 15e17;  // 150%
    uint public constant LEVERAGE_MIN = 1e17;  // 10%
    ICVaultRelayer public relayer;

    modifier increaseNonceOnlyRelayer(address lp, address _account, uint nonce) {
        require(msg.sender == address(relayer), "CVaultBSCFlipStorage: not relayer");
        require(_pools[lp].cpool != address(0), "CVaultBSCFlipStorage: not pool");
        require(accountOf(lp, _account).nonce == nonce, "CVaultBSCFlipStorage: invalid nonce");
        _;
        increaseNonce(lp, _account);
    }

    modifier validLeverage(uint128 leverage) {
        require(LEVERAGE_MIN <= leverage && leverage <= LEVERAGE_MAX, "CVaultBSCFlipStorage: leverage range should be [10%-150%]");
        _;
    }

    // ---------- INITIALIZER ----------

    function __CVaultBSCFlipStorage_init() internal initializer {
        __PausableUpgradeable_init();
    }

    // ---------- VIEW ----------

    function cpoolOf(address lp) public view returns(address) {
        return _pools[lp].cpool;
    }

    function flipOf(address lp) public view returns(address) {
        return _pools[lp].flip;
    }

    function stateOf(address lp, address account) public view returns(State) {
        return _pools[lp].accounts[account].state;
    }

    function accountOf(address lp, address account) public view returns(Account memory) {
        return _pools[lp].accounts[account];
    }

    // ---------- RESTRICTED ----------

    function setCVaultRelayer(address newRelayer) external onlyOwner {
        relayer = ICVaultRelayer(newRelayer);
    }

    function _setPool(address lp, address flip, address cpool) internal onlyOwner {
        require(_pools[lp].cpool == address(0) && _pools[lp].flip == address(0), "CVaultBSCFlipStorage: set already");
        _pools[lp].flip = flip;
        _pools[lp].cpool = cpool;
    }

    function increaseNonce(address lp, address _account) private {
        _pools[lp].accounts[_account].nonce++;
    }

    function convertState(address lp, address _account, State state) internal {
        Account storage account = _pools[lp].accounts[_account];
        State current = account.state;
        if (current == state) {
            return;
        }

        if (state == State.Idle) {
            require(current == State.Farming, "CVaultBSCFlipStorage: can't convert to Idle");
        } else if (state == State.Farming) {

        } else {
            revert("CVaultBSCFlipStorage: invalid state");
        }

        account.state = state;
    }
}
