// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";


contract TripleSlopeModel {
    using SafeMath for uint;

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint debt, uint floating) external pure returns (uint) {
        uint total = debt.add(floating);
        if (total == 0) return 0;

        uint utilization = debt.mul(10000).div(total);
        if (utilization < 5000) {
            // Less than 50% utilization - 10% APY
            return uint(10e16) / 365 days;
        } else if (utilization < 9500) {
            // Between 50% and 95% - 10%-25% APY
            return (10e16 + utilization.sub(5000).mul(15e16).div(4500)) / 365 days;
        } else if (utilization < 10000) {
            // Between 95% and 100% - 25%-100% APY
            return (25e16 + utilization.sub(9500).mul(75e16).div(500)) / 365 days;
        } else {
            // Not possible, but just in case - 100% APY
            return uint(100e16) / 365 days;
        }
    }
}
