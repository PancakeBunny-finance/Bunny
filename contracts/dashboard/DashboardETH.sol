// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/*
  ___                      _   _
 | _ )_  _ _ _  _ _ _  _  | | | |
 | _ \ || | ' \| ' \ || | |_| |_|
 |___/\_,_|_||_|_||_\_, | (_) (_)
                    |__/

*
* MIT License
* ===========
*
* Copyright (c) 2020 BunnyFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {PoolConstant} from "../library/PoolConstant.sol";
import "../interfaces/IVaultCollateral.sol";

import "./calculator/PriceCalculatorETH.sol";


contract DashboardETH is OwnableUpgradeable {
    using SafeMath for uint;

    PriceCalculatorETH public constant priceCalculator = PriceCalculatorETH(0xB73106688fdfee99578731aDb18c9689462B415a);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint tvl) {
        IVaultCollateral strategy = IVaultCollateral(pool);
        (, tvl) = priceCalculator.valueOfAsset(strategy.stakingToken(), strategy.balance());
    }

    /* ========== Pool Information ========== */

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        IVaultCollateral strategy = IVaultCollateral(pool);
        PoolConstant.PoolInfo memory poolInfo;

        uint collateral = strategy.collateralOf(account);
        (, uint collateralInUSD) = priceCalculator.valueOfAsset(strategy.stakingToken(), collateral);

        poolInfo.pool = pool;
        poolInfo.balance = collateralInUSD;
        poolInfo.principal = collateral;
        poolInfo.available = strategy.availableOf(account);
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.pBASE = strategy.realizedInETH(account);
        poolInfo.depositedAt = strategy.depositedAt(account);
        poolInfo.feeDuration = strategy.WITHDRAWAL_FEE_PERIOD();
        poolInfo.feePercentage = strategy.WITHDRAWAL_FEE();
        poolInfo.portfolio = portfolioOfPoolInUSD(pool, account);
        return poolInfo;
    }

    function poolsOf(address account, address[] memory pools) public view returns (PoolConstant.PoolInfo[] memory) {
        PoolConstant.PoolInfo[] memory results = new PoolConstant.PoolInfo[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            results[i] = infoOfPool(pools[i], account);
        }
        return results;
    }

    /* ========== Portfolio Calculation ========== */

    function portfolioOfPoolInUSD(address pool, address account) internal view returns (uint) {
        IVaultCollateral strategy = IVaultCollateral(pool);
        address stakingToken = strategy.stakingToken();

        (, uint collateralInUSD) = priceCalculator.valueOfAsset(stakingToken, strategy.collateralOf(account));
        (, uint availableInUSD) = priceCalculator.valueOfAsset(stakingToken, strategy.availableOf(account));
        (, uint profitInUSD) = priceCalculator.valueOfAsset(WETH, strategy.realizedInETH(account));
        return collateralInUSD.add(availableInUSD).add(profitInUSD);
    }

    function portfolioOf(address account, address[] memory pools) public view returns (uint deposits) {
        deposits = 0;
        for (uint i = 0; i < pools.length; i++) {
            deposits = deposits.add(portfolioOfPoolInUSD(pools[i], account));
        }
    }
}
