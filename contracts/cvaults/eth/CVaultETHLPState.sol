// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface CVaultETHLPState {
    enum State {
        Idle, Depositing, Farming, Withdrawing, UpdatingLeverage, Liquidating, EmergencyExited
    }

    struct Account {
        uint collateral;
        uint bscBNBDebt;         // BSC - Borrowing BNB shares
        uint bscFlipBalance;     // BSC - Farming FLIP amount
        uint128 leverage;
        uint112 nonce;
        uint64 updatedAt;
        uint64 depositedAt;
        address liquidator;
        State state;
        uint withdrawalRequestAmount;
    }

    struct Pool {
        address bscFlip;
        bool paused;
        uint totalCollateral;

        mapping (address => Account) accounts;
    }
}
