// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

library PotConstant {
    enum PotState {
        Opened,
        Closed,
        Cooked
    }

    struct PotInfo {
        uint potId;
        PotState state;
        uint supplyCurrent;
        uint supplyDonation;
        uint supplyInUSD;
        uint rewards;
        uint rewardsInUSD;
        uint minAmount;
        uint maxAmount;
        uint avgOdds;
        uint startedAt;
    }

    struct PotInfoMe {
        uint wTime;
        uint wCount;
        uint wValue;
        uint odds;
        uint available;
        uint lastParticipatedPot;
        uint depositedAt;
    }

    struct PotHistory {
        uint potId;
        uint users;
        uint rewardPerWinner;
        uint date;
        address[] winners;
    }
}
