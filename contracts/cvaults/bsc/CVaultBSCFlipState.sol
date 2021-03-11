// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface CVaultBSCFlipState {
    enum State {
        Idle, Farming
    }

    struct Account {
        uint nonce;
        State state;
    }

    struct Pool {
        address flip;
        address cpool;

        mapping (address => Account) accounts;
    }
}
