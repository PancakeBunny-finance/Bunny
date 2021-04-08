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

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IStrategy.sol";
import "../interfaces/IBunnyMinter.sol";
import "../interfaces/IBunnyChef.sol";

import "../vaults/legacy/BunnyPool.sol";
import "../vaults/VaultVenus.sol";
import "./calculator/PriceCalculatorBSC.sol";


contract DashboardBSC is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    PriceCalculatorBSC public constant priceCalculator = PriceCalculatorBSC(0x542c06a5dc3f27e0fbDc9FB7BC6748f26d54dDb0);

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant VaultCakeToCake = 0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD;

    IBunnyChef private constant bunnyChef = IBunnyChef(0x40e31876c4322bd033BAb028474665B12c4d04CE);
    BunnyPool private constant bunnyPool = BunnyPool(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);

    /* ========== STATE VARIABLES ========== */

    mapping(address => PoolConstant.PoolTypes) public poolTypes;
    mapping(address => uint) public pancakePoolIds;
    mapping(address => bool) public perfExemptions;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== Restricted Operation ========== */

    function setPoolType(address pool, PoolConstant.PoolTypes poolType) public onlyOwner {
        poolTypes[pool] = poolType;
    }

    function setPancakePoolId(address pool, uint pid) public onlyOwner {
        pancakePoolIds[pool] = pid;
    }

    function setPerfExemption(address pool, bool exemption) public onlyOwner {
        perfExemptions[pool] = exemption;
    }

    /* ========== View Functions ========== */

    function poolTypeOf(address pool) public view returns (PoolConstant.PoolTypes) {
        return poolTypes[pool];
    }

    /* ========== Utilization Calculation ========== */

    function utilizationOfPool(address pool) public view returns (uint liquidity, uint utilized) {
        if (poolTypes[pool] == PoolConstant.PoolTypes.Venus) {
            return VaultVenus(payable(pool)).getUtilizationInfo();
        }
        return (0, 0);
    }

    /* ========== Profit Calculation ========== */

    function calculateProfit(address pool, address account) public view returns (uint profit, uint profitInBNB) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];
        profit = 0;
        profitInBNB = 0;

        if (poolType == PoolConstant.PoolTypes.BunnyStake) {
            // profit as bnb
            (profit,) = priceCalculator.valueOfAsset(address(bunnyPool.rewardsToken()), bunnyPool.earned(account));
            profitInBNB = profit;
        }
        else if (poolType == PoolConstant.PoolTypes.Bunny) {
            // profit as bunny
            profit = bunnyChef.pendingBunny(pool, account);
            (profitInBNB,) = priceCalculator.valueOfAsset(BUNNY, profit);
        }
        else if (poolType == PoolConstant.PoolTypes.CakeStake || poolType == PoolConstant.PoolTypes.FlipToFlip || poolType == PoolConstant.PoolTypes.Venus) {
            // profit as underlying
            IStrategy strategy = IStrategy(pool);
            profit = strategy.earned(account);
            (profitInBNB,) = priceCalculator.valueOfAsset(strategy.stakingToken(), profit);
        }
        else if (poolType == PoolConstant.PoolTypes.FlipToCake || poolType == PoolConstant.PoolTypes.BunnyBNB) {
            // profit as cake
            IStrategy strategy = IStrategy(pool);
            profit = strategy.earned(account).mul(IStrategy(strategy.rewardsToken()).priceShare()).div(1e18);
            (profitInBNB,) = priceCalculator.valueOfAsset(CAKE, profit);
        }
    }

    function profitOfPool(address pool, address account) public view returns (uint profit, uint bunny) {
        (uint profitCalculated, uint profitInBNB) = calculateProfit(pool, account);
        profit = profitCalculated;
        bunny = 0;

        if (!perfExemptions[pool]) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.minter() != address(0)) {
                profit = profit.mul(70).div(100);
                bunny = IBunnyMinter(strategy.minter()).amountBunnyToMint(profitInBNB.mul(30).div(100));
            }

            if (strategy.bunnyChef() != address(0)) {
                bunny = bunny.add(bunnyChef.pendingBunny(pool, account));
            }
        }
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint tvl) {
        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (, tvl) = priceCalculator.valueOfAsset(address(bunnyPool.stakingToken()), bunnyPool.balance());
        }
        else {
            IStrategy strategy = IStrategy(pool);
            (, tvl) = priceCalculator.valueOfAsset(strategy.stakingToken(), strategy.balance());

            if (strategy.rewardsToken() == VaultCakeToCake) {
                IStrategy rewardsToken = IStrategy(strategy.rewardsToken());
                uint rewardsInCake = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
                (, uint rewardsInUSD) = priceCalculator.valueOfAsset(address(CAKE), rewardsInCake);
                tvl = tvl.add(rewardsInUSD);
            }
        }
    }

    /* ========== Pool Information ========== */

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfoBSC memory) {
        PoolConstant.PoolInfoBSC memory poolInfo;

        IStrategy strategy = IStrategy(pool);
        (uint pBASE, uint pBUNNY) = profitOfPool(pool, account);
        (uint liquidity, uint utilized) = utilizationOfPool(pool);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.utilized = utilized;
        poolInfo.liquidity = liquidity;
        poolInfo.pBASE = pBASE;
        poolInfo.pBUNNY = pBUNNY;

        PoolConstant.PoolTypes poolType = poolTypeOf(pool);
        if (poolType != PoolConstant.PoolTypes.BunnyStake && strategy.minter() != address(0)) {
            IBunnyMinter minter = IBunnyMinter(strategy.minter());
            poolInfo.depositedAt = strategy.depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }
        return poolInfo;
    }

    function poolsOf(address account, address[] memory pools) public view returns (PoolConstant.PoolInfoBSC[] memory) {
        PoolConstant.PoolInfoBSC[] memory results = new PoolConstant.PoolInfoBSC[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            results[i] = infoOfPool(pools[i], account);
        }
        return results;
    }

    /* ========== Portfolio Calculation ========== */

    function stakingTokenValueInUSD(address pool, address account) internal view returns (uint tokenInUSD) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];

        address stakingToken;
        if (poolType == PoolConstant.PoolTypes.BunnyStake) {
            stakingToken = BUNNY;
        } else {
            stakingToken = IStrategy(pool).stakingToken();
        }

        if (stakingToken == address(0)) return 0;
        (, tokenInUSD) = priceCalculator.valueOfAsset(stakingToken, IStrategy(pool).principalOf(account));
    }

    function portfolioOfPoolInUSD(address pool, address account) internal view returns (uint) {
        uint tokenInUSD = stakingTokenValueInUSD(pool, account);
        (, uint profitInBNB) = calculateProfit(pool, account);
        uint profitInBUNNY = 0;

        if (!perfExemptions[pool]) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.minter() != address(0)) {
                profitInBNB = profitInBNB.mul(70).div(100);
                profitInBUNNY = IBunnyMinter(strategy.minter()).amountBunnyToMint(profitInBNB.mul(30).div(100));
            }

            if ((poolTypes[pool] == PoolConstant.PoolTypes.Bunny || poolTypes[pool] == PoolConstant.PoolTypes.BunnyBNB
            || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip)
                && strategy.bunnyChef() != address(0)) {
                profitInBUNNY = profitInBUNNY.add(bunnyChef.pendingBunny(pool, account));
            }
        }

        (, uint profitBNBInUSD) = priceCalculator.valueOfAsset(WBNB, profitInBNB);
        (, uint profitBUNNYInUSD) = priceCalculator.valueOfAsset(BUNNY, profitInBUNNY);
        return tokenInUSD.add(profitBNBInUSD).add(profitBUNNYInUSD);
    }

    function portfolioOf(address account, address[] memory pools) public view returns (uint deposits) {
        deposits = 0;
        for (uint i = 0; i < pools.length; i++) {
            deposits = deposits.add(portfolioOfPoolInUSD(pools[i], account));
        }
    }
}
