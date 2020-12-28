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

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "./library/SafeDecimal.sol";
import "./library/OwnableWithKeeper.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IBunnyMinter.sol";
import "./vaults/legacy/BunnyPool.sol";
import "./vaults/legacy/BunnyBNBPool.sol";
import "./vaults/legacy/StrategyCompoundFLIP.sol";
import "./vaults/legacy/StrategyCompoundCake.sol";
import "./vaults/legacy/CakeFlipVault.sol";
import "./vaults/VaultFlipToCake.sol";
import {PoolConstant} from "./library/PoolConstant.sol";


contract Dashboard is OwnableWithKeeper {
    using SafeMath for uint;
    using SafeDecimal for uint;

    uint private constant BLOCK_PER_YEAR = 10512000;

    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IBEP20 private constant BUSD = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);

    address private constant BNB_BUSD_POOL = 0x1B96B92314C44b159149f7E0303511fB2Fc4774f;
    IMasterChef private constant master = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    IPancakeFactory private constant factory = IPancakeFactory(0xBCfCcbde45cE874adCB698cC183deBcF17952812);

    BunnyPool private constant bunnyPool = BunnyPool(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);
    BunnyBNBPool private constant bunnyBnbPool = BunnyBNBPool(0xc80eA568010Bca1Ad659d1937E17834972d66e0D);

    mapping(address => address) private pairAddresses;
    mapping(address => PoolConstant.PoolTypes) private poolTypes;
    mapping(address => uint) private poolIds;
    mapping(address => bool) private legacyPools;
    mapping(address => address) private linkedPools;

    /* ========== Restricted Operation ========== */

    function setPairAddress(address asset, address pair) external onlyAuthorized {
        pairAddresses[asset] = pair;
    }

    function setPoolType(address pool, PoolConstant.PoolTypes poolType) external onlyAuthorized {
        poolTypes[pool] = poolType;
    }

    function setPoolId(address pool, uint pid) external onlyAuthorized {
        poolIds[pool] = pid;
    }

    function setLegacyPool(address pool, bool legacy) external onlyAuthorized {
        legacyPools[pool] = legacy;
    }

    function setLinkedPool(address pool, address linked) external onlyAuthorized {
        linkedPools[pool] = linked;
    }

    /* ========== Value Calculation ========== */

    function priceOfBNB() view public returns (uint) {
        return BUSD.balanceOf(BNB_BUSD_POOL).mul(1e18).div(WBNB.balanceOf(BNB_BUSD_POOL));
    }

    function priceOfBunny() view public returns (uint) {
        (, uint bunnyPriceInUSD) = valueOfAsset(address(BUNNY), 1e18);
        return bunnyPriceInUSD;
    }

    function valueOfAsset(address asset, uint amount) public view returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == address(WBNB)) {
            valueInBNB = amount;
            valueInUSD = amount.mul(priceOfBNB()).div(1e18);
        } else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IPancakePair(asset).token0() == address(WBNB) || IPancakePair(asset).token1() == address(WBNB)) {
                valueInBNB = amount.mul(WBNB.balanceOf(address(asset))).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else {
                uint balanceToken0 = IBEP20(IPancakePair(asset).token0()).balanceOf(asset);
                (uint token0PriceInBNB,) = valueOfAsset(IPancakePair(asset).token0(), 1e18);

                valueInBNB = amount.mul(balanceToken0).mul(2).mul(token0PriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            }
        } else {
            address pairAddress = pairAddresses[asset];
            if (pairAddress == address(0)) {
                pairAddress = address(WBNB);
            }

            address pair = factory.getPair(asset, pairAddress);
            valueInBNB = IBEP20(pairAddress).balanceOf(pair).mul(amount).div(IBEP20(asset).balanceOf(pair));
            if (pairAddress != address(WBNB)) {
                (uint pairValueInBNB,) = valueOfAsset(pairAddress, 1e18);
                valueInBNB = valueInBNB.mul(pairValueInBNB).div(1e18);
            }
            valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
        }
    }

    /* ========== APY Calculation ========== */

    function basicCompound(uint pid, uint compound) private view returns (uint) {
        (address token, uint allocPoint,,) = master.poolInfo(pid);
        (uint valueInBNB,) = valueOfAsset(token, IBEP20(token).balanceOf(address(master)));

        (uint cakePriceInBNB,) = valueOfAsset(address(CAKE), 1e18);
        uint cakePerYearOfPool = master.cakePerBlock().mul(BLOCK_PER_YEAR).mul(allocPoint).div(master.totalAllocPoint());
        uint apr = cakePriceInBNB.mul(cakePerYearOfPool).div(valueInBNB);
        return apr.div(compound).add(1e18).power(compound).sub(1e18);
    }

    function compoundingAPY(uint pid, uint compound, PoolConstant.PoolTypes poolType) private view returns (uint) {
        if (poolType == PoolConstant.PoolTypes.BunnyStake) {
            (uint bunnyPriceInBNB,) = valueOfAsset(address(BUNNY), 1e18);
            (uint rewardsPriceInBNB,) = valueOfAsset(address(bunnyPool.rewardsToken()), 1e18);

            uint poolSize = bunnyPool.totalSupply();
            if (poolSize == 0) {
                poolSize = 1e18;
            }

            uint rewardsOfYear = bunnyPool.rewardRate().mul(1e18).div(poolSize).mul(365 days);
            return rewardsOfYear.mul(rewardsPriceInBNB).div(bunnyPriceInBNB);
        } else if (poolType == PoolConstant.PoolTypes.BunnyFlip) {
            (uint flipPriceInBNB,) = valueOfAsset(address(bunnyBnbPool.token()), 1e18);
            (uint bunnyPriceInBNB,) = valueOfAsset(address(BUNNY), 1e18);

            IBunnyMinter minter = IBunnyMinter(address(bunnyBnbPool.minter()));
            uint mintPerYear = minter.amountBunnyToMintForBunnyBNB(1e18, 365 days);
            return mintPerYear.mul(bunnyPriceInBNB).div(flipPriceInBNB);
        } else if (poolType == PoolConstant.PoolTypes.CakeStake || poolType == PoolConstant.PoolTypes.FlipToFlip) {
            return basicCompound(pid, compound);
        } else if (poolType == PoolConstant.PoolTypes.FlipToCake) {
            // https://en.wikipedia.org/wiki/Geometric_series
            uint dailyApyOfPool = basicCompound(pid, 1).div(compound);
            uint dailyApyOfCake = basicCompound(0, 1).div(compound);
            uint cakeAPY = basicCompound(0, 365);
            return dailyApyOfPool.mul(cakeAPY).div(dailyApyOfCake);
        }
        return 0;
    }

    function apyOfPool(address pool, uint compound) public view returns (uint apyPool, uint apyBunny) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];
        uint _apy = compoundingAPY(poolIds[pool], compound, poolType);
        apyPool = _apy;
        apyBunny = 0;

        if (poolType == PoolConstant.PoolTypes.BunnyStake || poolType == PoolConstant.PoolTypes.BunnyFlip) {

        } else {
            if (legacyPools[pool]) {
                IBunnyMinter minter = IBunnyMinter(0x0B4A714AAf59E46cb1900E3C031017Fd72667EfE);
                if (minter.isMinter(pool)) {
                    uint compounding = _apy.mul(70).div(100);
                    uint inflation = priceOfBunny().mul(1e18).div(priceOfBNB().mul(1e18).div(minter.bunnyPerProfitBNB()));
                    uint bunnyIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

                    apyPool = compounding;
                    apyBunny = bunnyIncentive;
                }
            } else {
                IStrategy strategy = IStrategy(pool);
                if (strategy.minter() != address(0)) {
                    uint compounding = _apy.mul(70).div(100);
                    uint inflation = priceOfBunny().mul(1e18).div(priceOfBNB().mul(1e18).div(IBunnyMinter(strategy.minter()).bunnyPerProfitBNB()));
                    uint bunnyIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

                    apyPool = compounding;
                    apyBunny = bunnyIncentive;
                }
            }
        }
    }

    /* ========== Profit Calculation ========== */

    function profitOfPool_legacy(address pool, address account) public view returns (uint usd, uint bnb, uint bunny, uint cake) {
        usd = 0;
        bnb = 0;
        bunny = 0;
        cake = 0;

        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (uint profitInBNB,) = valueOfAsset(address(bunnyPool.rewardsToken()), bunnyPool.earned(account));
            bnb = profitInBNB;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            IBunnyMinter minter = bunnyBnbPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                bunny = minter.amountBunnyToMintForBunnyBNB(bunnyBnbPool.balanceOf(account), block.timestamp.sub(bunnyBnbPool.depositedAt(account)));
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake) {
            StrategyCompoundCake strategyCompoundCake = StrategyCompoundCake(pool);
            if (strategyCompoundCake.balanceOf(account) > strategyCompoundCake.principalOf(account)) {
                (, uint cakeInUSD) = valueOfAsset(address(CAKE), strategyCompoundCake.balanceOf(account).sub(strategyCompoundCake.principalOf(account)));

                IBunnyMinter minter = strategyCompoundCake.minter();
                if (address(minter) != address(0) && minter.isMinter(pool)) {
                    uint performanceFee = minter.performanceFee(cakeInUSD);
                    uint performanceFeeInBNB = performanceFee.mul(1e18).div(priceOfBNB());
                    usd = cakeInUSD.sub(performanceFee);
                    bunny = minter.amountBunnyToMint(performanceFeeInBNB);
                } else {
                    usd = cakeInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            StrategyCompoundFLIP strategyCompoundFlip = StrategyCompoundFLIP(pool);
            if (strategyCompoundFlip.balanceOf(account) > strategyCompoundFlip.principalOf(account)) {
                (, uint flipInUSD) = valueOfAsset(address(strategyCompoundFlip.token()), strategyCompoundFlip.balanceOf(account).sub(strategyCompoundFlip.principalOf(account)));

                IBunnyMinter minter = strategyCompoundFlip.minter();
                if (address(minter) != address(0) && minter.isMinter(pool)) {
                    uint performanceFee = minter.performanceFee(flipInUSD);
                    uint performanceFeeInBNB = performanceFee.mul(1e18).div(priceOfBNB());
                    usd = flipInUSD.sub(performanceFee);
                    bunny = minter.amountBunnyToMint(performanceFeeInBNB);
                } else {
                    usd = flipInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
            CakeFlipVault flipVault = CakeFlipVault(pool);
            uint profitInCake = flipVault.earned(account).mul(flipVault.rewardsToken().priceShare()).div(1e18);

            IBunnyMinter minter = flipVault.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                uint performanceFeeInCake = minter.performanceFee(profitInCake);
                (uint performanceFeeInBNB,) = valueOfAsset(address(CAKE), performanceFeeInCake);
                cake = profitInCake.sub(performanceFeeInCake);
                bunny = minter.amountBunnyToMint(performanceFeeInBNB);
            } else {
                cake = profitInCake;
            }
        }
    }

    function profitOfPool_v2(address pool, address account) public view returns (uint usd, uint bnb, uint bunny, uint cake) {
        usd = 0;
        bnb = 0;
        bunny = 0;
        cake = 0;

        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (uint profitInBNB,) = valueOfAsset(address(bunnyPool.rewardsToken()), bunnyPool.earned(account));
            bnb = profitInBNB;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            IBunnyMinter minter = bunnyBnbPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                bunny = minter.amountBunnyToMintForBunnyBNB(bunnyBnbPool.balanceOf(account), block.timestamp.sub(bunnyBnbPool.depositedAt(account)));
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.earned(account) > 0) {
                (, uint profitInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balanceOf(account).sub(strategy.principalOf(account)));
                if (strategy.minter() != address(0)) {
                    IBunnyMinter minter = IBunnyMinter(strategy.minter());
                    uint performanceFee = minter.performanceFee(profitInUSD);
                    uint performanceFeeInBNB = performanceFee.mul(1e18).div(priceOfBNB());
                    usd = profitInUSD.sub(performanceFee);
                    bunny = minter.amountBunnyToMint(performanceFeeInBNB);
                } else {
                    usd = profitInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.earned(account) > 0) {
                uint profitInCAKE = strategy.earned(account).mul(IStrategy(strategy.rewardsToken()).priceShare()).div(1e18);
                if (strategy.minter() != address(0)) {
                    IBunnyMinter minter = IBunnyMinter(strategy.minter());
                    uint performanceFeeInCake = minter.performanceFee(profitInCAKE);
                    (uint performanceFeeInBNB,) = valueOfAsset(address(CAKE), performanceFeeInCake);
                    cake = profitInCAKE.sub(performanceFeeInCake);
                    bunny = minter.amountBunnyToMint(performanceFeeInBNB);
                } else {
                    cake = profitInCAKE;
                }
            }
        }
    }

    function profitOfPool(address pool, address account) public view returns (uint usd, uint bnb, uint bunny, uint cake) {
        return legacyPools[pool] ? profitOfPool_legacy(pool, account) : profitOfPool_v2(pool, account);
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool_legacy(address pool) public view returns (uint) {
        if (pool == address(0)) {
            return 0;
        }

        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyPool.stakingToken()), bunnyPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyBnbPool.token()), bunnyBnbPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake) {
            (, uint tvlInUSD) = valueOfAsset(address(CAKE), IStrategyLegacy(pool).balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            StrategyCompoundFLIP strategyCompoundFlip = StrategyCompoundFLIP(pool);

            (, uint tvlInUSD) = valueOfAsset(address(strategyCompoundFlip.token()), strategyCompoundFlip.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
            CakeFlipVault flipVault = CakeFlipVault(pool);
            IStrategy rewardsToken = IStrategy(address(flipVault.rewardsToken()));

            (, uint tvlInUSD) = valueOfAsset(address(flipVault.stakingToken()), flipVault.totalSupply());

            uint rewardsInCake = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
            (, uint rewardsInUSD) = valueOfAsset(address(CAKE), rewardsInCake);
            return tvlInUSD.add(rewardsInUSD);
        }
        return 0;
    }

    function tvlOfPool_v2(address pool) public view returns (uint) {
        if (pool == address(0)) {
            return 0;
        }

        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyPool.stakingToken()), bunnyPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyBnbPool.token()), bunnyBnbPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());

            IStrategy rewardsToken = IStrategy(strategy.rewardsToken());
            uint rewardsInCake = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
            (, uint rewardsInUSD) = valueOfAsset(address(CAKE), rewardsInCake);
            return tvlInUSD.add(rewardsInUSD);
        }
        return 0;
    }

    function tvlOfPool(address pool) public view returns (uint) {
        if (legacyPools[pool]) {
            return tvlOfPool_legacy(pool);
        }

        address linked = linkedPools[pool];
        return linked != address(0) ? tvlOfPool_v2(pool).add(tvlOfPool_legacy(linked)) : tvlOfPool_v2(pool);
    }

    /* ========== Pool Information ========== */

    function infoOfPool_legacy(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        PoolConstant.PoolInfo memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        IStrategyLegacy strategy = IStrategyLegacy(pool);
        (uint profitUSD, uint profitBNB, uint profitBUNNY, uint profitCAKE) = profitOfPool(pool, account);
        (uint apyPool, uint apyBunny) = apyOfPool(pool, 365);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.apyPool = apyPool;
        poolInfo.apyBunny = apyBunny;
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.pUSD = profitUSD;
        poolInfo.pBNB = profitBNB;
        poolInfo.pBUNNY = profitBUNNY;
        poolInfo.pCAKE = profitCAKE;

        if (poolTypes[pool] != PoolConstant.PoolTypes.BunnyStake) {
            IBunnyMinter minter = IBunnyMinter(0x0B4A714AAf59E46cb1900E3C031017Fd72667EfE);
            poolInfo.depositedAt = StrategyCompoundCake(pool).depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }
        return poolInfo;
    }

    function infoOfPool_v2(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        PoolConstant.PoolInfo memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        IStrategy strategy = IStrategy(pool);
        (uint profitUSD, uint profitBNB, uint profitBUNNY, uint profitCAKE) = profitOfPool(pool, account);
        (uint apyPool, uint apyBunny) = apyOfPool(pool, 365);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.apyPool = apyPool;
        poolInfo.apyBunny = apyBunny;
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.pUSD = profitUSD;
        poolInfo.pBNB = profitBNB;
        poolInfo.pBUNNY = profitBUNNY;
        poolInfo.pCAKE = profitCAKE;

        if (strategy.minter() != address(0)) {
            IBunnyMinter minter = IBunnyMinter(strategy.minter());
            poolInfo.depositedAt = strategy.depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }

        return poolInfo;
    }

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        return legacyPools[pool] ? infoOfPool_legacy(pool, account) : infoOfPool_v2(pool, account);
    }
}
