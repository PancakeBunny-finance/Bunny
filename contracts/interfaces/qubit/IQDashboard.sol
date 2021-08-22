// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../../library/QConstant.sol";

interface IQDashboard {
    struct LockerData {
        uint totalLocked;
        uint locked;
        uint totalScore;
        uint score;
        uint available;
        uint expiry;
    }

    struct MarketData {
        uint apySupply;
        uint apySupplyQBT;
        uint apyMySupplyQBT;
        uint apyBorrow;
        uint apyBorrowQBT;
        uint apyMyBorrowQBT;
        uint liquidity;
        uint collateralFactor;
        bool membership;
        uint supply;
        uint borrow;
        uint totalSupply;
        uint totalBorrow;
        uint supplyBoosted;
        uint borrowBoosted;
        uint totalSupplyBoosted;
        uint totalBorrowBoosted;
    }

    struct PortfolioData {
        int userApy;
        uint userApySupply;
        uint userApySupplyQBT;
        uint userApyBorrow;
        uint userApyBorrowQBT;
        uint supplyInUSD;
        uint borrowInUSD;
        uint limitInUSD;
    }

    struct AccountLiquidityData {
        address account;
        uint marketCount;
        uint collateralUSD;
        uint borrowUSD;
    }

    function statusOf(address account, address[] memory markets)
        external
        view
        returns (LockerData memory, MarketData[] memory);

    function userApyDistributionOf(address account, address market)
        external
        view
    returns (uint userApySupplyQBT, uint userApyBorrowQBT);
    function portfolioDataOf(address account) external view returns (uint supplyAPY, uint borrowAPY, uint qubitAPYsup, uint qubitAPYbor);
}
