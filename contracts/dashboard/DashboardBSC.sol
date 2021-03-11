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
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../library/SafeDecimal.sol";

import "../interfaces/IMasterChef.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IBunnyMinter.sol";
import "../interfaces/IBunnyChef.sol";
import "../interfaces/AggregatorV3Interface.sol";

import "../vaults/legacy/BunnyPool.sol";
import "../vaults/legacy/BunnyBNBPool.sol";
import "../vaults/VaultFlipToCake.sol";
import "../vaults/VaultBunny.sol";
import "../vaults/VaultBunnyBNB.sol";
import "../cvaults/bsc/bank/BankBNB.sol";
import "./DashboardHelper.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract DashboardBSC is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    uint private constant BLOCK_PER_YEAR = 10512000;
    uint private constant BLOCK_PER_DAY = 28800;

    address private constant VENUS = 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63;
    address private constant CAKEBNBAddr = 0xA527a61703D82139F8a06Bc30097cC9CAA2df5A6;

    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);

    IBunnyChef private constant bunnyChef = IBunnyChef(0x40e31876c4322bd033BAb028474665B12c4d04CE);
    IMasterChef private constant pancakeChef = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    IPancakeFactory private constant factory = IPancakeFactory(0xBCfCcbde45cE874adCB698cC183deBcF17952812);
    AggregatorV3Interface private constant bnbPriceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);

    BunnyPool private constant bunnyPool = BunnyPool(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);
    BunnyBNBPool private constant bunnyBnbPool = BunnyBNBPool(0xc80eA568010Bca1Ad659d1937E17834972d66e0D);

    VaultBunny private constant vaultBunny = VaultBunny(0xb037581cF0cE10b04C4735443d95e0C93db5d940);
    VaultBunnyBNB private constant vaultBunnyBNB = VaultBunnyBNB(0x69FF781Cf86d42af9Bf93c06B8bE0F16a2905cBC);

    /* ========== STATE VARIABLES ========== */

    address payable public bankBNBAddress;
    address payable public bscFlipAddress;
    address payable public relayerAddress;
    address private helperAddress;
    mapping(address => address) private pairAddresses;
    mapping(address => PoolConstant.PoolTypes) private poolTypes;
    mapping(address => uint) private poolIds;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== Restricted Operation ========== */

    function setBankBNBAddress(address payable _bankBNBAddress) external onlyOwner {
        bankBNBAddress = _bankBNBAddress;
    }

    function setBscFlipAddress(address payable _bscFlipAddress) external onlyOwner {
        bscFlipAddress = _bscFlipAddress;
    }

    function setRelayerAddress(address payable _relayerAddress) external onlyOwner {
        relayerAddress = _relayerAddress;
    }

    function setPairAddress(address asset, address pair) external onlyOwner {
        pairAddresses[asset] = pair;
    }

    function setPoolType(address pool, PoolConstant.PoolTypes poolType) external onlyOwner {
        poolTypes[pool] = poolType;
    }

    function setPoolId(address pool, uint pid) external onlyOwner {
        poolIds[pool] = pid;
    }

    function setDashboardHelperAddress(address _helpAddress) external onlyOwner {
        helperAddress = _helpAddress;
    }

    /* ========== Value Calculation ========== */

    function priceOfBNB() view public returns (uint) {
        (, int price, , ,) = bnbPriceFeed.latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfBunny() view public returns (uint) {
        (, uint bunnyPriceInUSD) = valueOfAsset(address(BUNNY), 1e18);
        return bunnyPriceInUSD;
    }

    function pricesInUSD(address[] memory assets) public view returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            (, uint valueInUSD) = valueOfAsset(assets[i], 1e18);
            prices[i] = valueInUSD;
        }
        return prices;
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

    function cakeCompound(uint pid, uint compound) private view returns (uint) {
        if (pid >= pancakeChef.poolLength()) return 0;

        (address token, uint allocPoint,,) = pancakeChef.poolInfo(pid);
        (uint valueInBNB,) = valueOfAsset(token, IBEP20(token).balanceOf(address(pancakeChef)));
        if (valueInBNB == 0) return 0;

        (uint cakePriceInBNB,) = valueOfAsset(address(CAKE), 1e18);
        uint cakePerYearOfPool = pancakeChef.cakePerBlock().mul(BLOCK_PER_YEAR).mul(allocPoint).div(pancakeChef.totalAllocPoint());
        uint apr = cakePriceInBNB.mul(cakePerYearOfPool).div(valueInBNB);
        return apr.div(compound).add(1e18).power(compound).sub(1e18);
    }

    function bunnyCompound(address vault, uint compound) private view returns (uint) {
        IBunnyChef.VaultInfo memory vaultInfo = bunnyChef.vaultInfoOf(vault);
        if (vaultInfo.token == address(0)) return 0;

        (, uint valueInUSD) = valueOfAsset(vaultInfo.token, IStrategy(vault).totalSupply());
        if (valueInUSD == 0) return 0;

        uint bunnyPerYearOfPool = bunnyChef.bunnyPerBlock().mul(BLOCK_PER_YEAR).mul(vaultInfo.allocPoint).div(bunnyChef.totalAllocPoint());
        uint apr = priceOfBunny().mul(bunnyPerYearOfPool).div(valueInUSD);
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
        }
        else if (poolType == PoolConstant.PoolTypes.BunnyFlip) {
            (uint flipPriceInBNB,) = valueOfAsset(address(bunnyBnbPool.token()), 1e18);
            (uint bunnyPriceInBNB,) = valueOfAsset(address(BUNNY), 1e18);

            IBunnyMinter minter = IBunnyMinter(address(bunnyBnbPool.minter()));
            uint mintPerYear = minter.amountBunnyToMintForBunnyBNB(1e18, 365 days);
            return mintPerYear.mul(bunnyPriceInBNB).div(flipPriceInBNB);
        }
        else if (poolType == PoolConstant.PoolTypes.CakeStake || poolType == PoolConstant.PoolTypes.FlipToFlip) {
            return cakeCompound(pid, compound);
        }
        else if (poolType == PoolConstant.PoolTypes.FlipToCake || poolType == PoolConstant.PoolTypes.BunnyBNB) {
            // https://en.wikipedia.org/wiki/Geometric_series
            uint dailyApyOfPool = cakeCompound(pid, 1).div(compound);
            uint dailyApyOfCake = cakeCompound(0, 1).div(compound);
            uint cakeAPY = cakeCompound(0, 365);
            return dailyApyOfPool.mul(cakeAPY).div(dailyApyOfCake);
        }
        return 0;
    }

    function apyOfPool(address pool, uint compound) public view returns (uint apyPool, uint apyBunny) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];
        uint _apy = compoundingAPY(poolIds[pool], compound, poolType);
        apyPool = _apy;
        apyBunny = 0;

        if (poolType == PoolConstant.PoolTypes.Liquidity) {

        }
        else if (poolType == PoolConstant.PoolTypes.BunnyStake || poolType == PoolConstant.PoolTypes.BunnyFlip) {

        }
        else if (poolType == PoolConstant.PoolTypes.Bunny) {
            apyBunny = bunnyCompound(address(vaultBunny), 1);
        }
        else if (poolType == PoolConstant.PoolTypes.BunnyBNB) {
            VaultBunnyBNB vaultBunnyBNB = VaultBunnyBNB(pool);
            if (!vaultBunnyBNB.pidAttached()) {
                _apy = 0;
            }

            IStrategy strategy = IStrategy(pool);
            if (strategy.minter() != address(0)) {
                uint compounding = _apy.mul(70).div(100);
                uint inflation = priceOfBunny().mul(1e18).div(priceOfBNB().mul(1e18).div(IBunnyMinter(strategy.minter()).bunnyPerProfitBNB()));
                uint bunnyIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

                apyPool = compounding;
                apyBunny = bunnyIncentive;
            }

            if (strategy.bunnyChef() != address(0)) {
                apyBunny = apyBunny.add(bunnyCompound(address(vaultBunnyBNB), 1));
            }
        }
        else {
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

    function apyOfLiquidity(address pool, uint amount) public view returns (
        uint apyPool, uint apyBunny, uint apyBorrow, uint venusBorrow, uint venusSupply, uint distributionBorrow, uint distributionSupply) {
        BankBNB bankBNB = BankBNB(bankBNBAddress);
        BankConfig config = bankBNB.config();

        (,uint utilized) = bankBNB.getUtilizationInfo();
        apyBorrow = config.getInterestRate(utilized, bankBNB.totalLocked()).mul(1 days).add(1e18).power(365).sub(1e18); // x0.9 (bps) lender

        DashboardHelper dashboardHelper = DashboardHelper(helperAddress);
        (venusBorrow, venusSupply) = dashboardHelper.apyOfVenus();
        (uint _priceBNB,) = valueOfAsset(VENUS, 1e18);
        (distributionBorrow, distributionSupply) = dashboardHelper.apyOfDistribution(_priceBNB);
//        apyBunny = ;  // TODO minter

        apyPool = dashboardHelper.calculateAPY(amount, venusBorrow, distributionBorrow, distributionSupply.add(venusSupply));
        // TODO check x0.9 (bps) - .mul(config.getReservePoolBps().mul(9).div(10e18)).div(1e18);
    }

    /* ========== Profit Calculation ========== */

    function profitOfPool(address pool, address account) public view returns (uint usd, uint bnb, uint bunny, uint cake) {
        usd = 0;
        bnb = 0;
        bunny = 0;
        cake = 0;

        if (poolTypes[pool] == PoolConstant.PoolTypes.Liquidity) {

        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (uint profitInBNB,) = valueOfAsset(address(bunnyPool.rewardsToken()), bunnyPool.earned(account));
            bnb = profitInBNB;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            IBunnyMinter minter = bunnyBnbPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                bunny = minter.amountBunnyToMintForBunnyBNB(bunnyBnbPool.balanceOf(account), block.timestamp.sub(bunnyBnbPool.depositedAt(account)));
            }
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.Bunny) {
            bunny = bunnyChef.pendingBunny(pool, account);
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyBNB) {
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
            bunny = bunny.add(bunnyChef.pendingBunny(pool, account));
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
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
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
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

    function profitOfLiquidity(address pool, address account) public view returns(uint usd, uint bnb, uint bunny) {
        usd = 0;
        bnb = 0;
        bunny = 0;

        if (pool == address(0)) {

        } else {
            BankBNB bankBNB = BankBNB(bankBNBAddress);
            uint balance = bankBNB.balanceOf(account);
            uint valueOfBalance = balance.mul(bankBNB.totalLiquidity()).div(bankBNB.totalSupply());
            if (valueOfBalance > balance) {
                bnb = valueOfBalance.sub(balance);
            }
            usd = bnb.mul(priceOfBNB());
        }
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint) {
        if (pool == address(0)) {
            return 0;
        }

        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyPool.stakingToken()), bunnyPool.balance());
            return tvlInUSD;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            (, uint tvlInUSD) = valueOfAsset(address(bunnyBnbPool.token()), bunnyBnbPool.balance());
            return tvlInUSD;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.Bunny) {
            (, uint tvlInUSD) = valueOfAsset(vaultBunny.stakingToken(), IStrategy(vaultBunny).totalSupply());
            return tvlInUSD;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyBNB) {
            (, uint tvlInUSD) = valueOfAsset(vaultBunnyBNB.stakingToken(), IStrategy(vaultBunnyBNB).totalSupply());
            return tvlInUSD;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());
            return tvlInUSD;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());

            IStrategy rewardsToken = IStrategy(strategy.rewardsToken());
            uint rewardsInCake = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
            (, uint rewardsInUSD) = valueOfAsset(address(CAKE), rewardsInCake);
            return tvlInUSD.add(rewardsInUSD);
        }
        return 0;
    }

    /* ========== Pool Information ========== */

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfoBSC memory) {
        PoolConstant.PoolInfoBSC memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        IStrategy strategy = IStrategy(pool);
        (uint profitUSD, uint profitBNB, uint profitBUNNY, uint profitCAKE) = profitOfPool(pool, account);
        (uint apyPool, uint apyBunny) = apyOfPool(pool, 365);
//
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

        if (poolTypes[pool] != PoolConstant.PoolTypes.BunnyStake && strategy.minter() != address(0)) {
            IBunnyMinter minter = IBunnyMinter(strategy.minter());
            poolInfo.depositedAt = strategy.depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }
        return poolInfo;
    }

    // TODO expand Venus, IStrategy
    function infoOfLiquidityPool(address pool, address account) public view returns (PoolConstant.LiquidityPoolInfo memory) {
        PoolConstant.LiquidityPoolInfo memory poolInfo;
        if (bankBNBAddress == address(0)) {
            return poolInfo;
        }

        BankBNB bankBNB = BankBNB(bankBNBAddress);

        //        IStrategy strategy = IStrategy(pool);
        (uint profitUSD, uint profitBNB, uint profitBUNNY) = profitOfLiquidity(pool, account);
        (uint liquidity, uint utilized) = bankBNB.getUtilizationInfo();
        (uint apyPool, uint apyBunny, uint apyBorrow,,,,) = apyOfLiquidity(bankBNBAddress, liquidity.sub(utilized));

        // TODO debt apy
//
        poolInfo.pool = bankBNBAddress;
        poolInfo.balance = bankBNB.principalOf(account).add(profitBNB);
        poolInfo.principal = bankBNB.principalOf(account);
        poolInfo.holding = bankBNB.balanceOf(account);

        poolInfo.apyPool = apyPool;
        poolInfo.apyBunny = apyBunny; // TODO
        poolInfo.apyBorrow = apyBorrow;
//
        poolInfo.tvl = liquidity;
        poolInfo.utilized = utilized;
//
        poolInfo.pBNB = profitBNB;
        poolInfo.pBUNNY = profitBUNNY; // TODO

        return poolInfo;
    }

    /* ========== Evaluation ========== */

    function stakingToken(address pool) internal view returns (address) {
        if (pool == address(bunnyPool)) {
            return address(bunnyPool.stakingToken());
        } else if (pool == address(bunnyBnbPool)) {
            return address(bunnyBnbPool.token());
        } else {
            return IStrategy(pool).stakingToken();
        }
    }

    function evaluate(address account, address[] memory pools) public view returns (uint deposits) {
        deposits = 0;
        for (uint i = 0; i < pools.length; i++) {
            (uint profitUSD, uint profitBNB, uint profitBUNNY, uint profitCAKE) = profitOfPool(pools[i], account);
            (, uint tokenEvaluated) = valueOfAsset(stakingToken(pools[i]), IStrategy(pools[i]).principalOf(account));
            (, uint bunnyEvaluated) = valueOfAsset(address(BUNNY), profitBUNNY);
            (, uint cakeEvaluated) = valueOfAsset(address(CAKE), profitCAKE);

            deposits = deposits.add(
                tokenEvaluated
                .add(profitUSD)
                .add(profitBNB.mul(priceOfBNB()).div(1e18))
                .add(bunnyEvaluated)
                .add(cakeEvaluated)
            );
        }
    }

    /* ========== Predict amount ========== */

    function predict(address lp, address flip, address _account, uint collateralETH, uint collateralBSC, uint leverage, uint debtBNB) public view returns(
        uint newCollateralBSC,
        uint newDebtBNB
    ) {
        (newCollateralBSC, newDebtBNB) = DashboardHelper(helperAddress).predict(lp, flip, _account, collateralETH, collateralBSC, leverage, debtBNB);
    }

    function withdrawAmountToBscTokens(address lp, address _account, uint leverage, uint amount) public view returns(uint bnbAmount, uint pairAmount, uint bnbOfPair) {
        (bnbAmount, pairAmount, bnbOfPair) = DashboardHelper(helperAddress).withdrawAmountToBscTokens(lp, _account, leverage, amount);
    }

    function collateralRatio(address lp, uint lpAmount, address flip, uint flipAmount, uint debt) public view returns(uint) {
        return DashboardHelper(helperAddress).collateralRatio(lp, lpAmount, flip, flipAmount, debt);
    }
}
