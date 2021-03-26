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

import "../library/SafeDecimal.sol";

import "../interfaces/IPancakePair.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IBunnyMinter.sol";
import "../interfaces/IBunnyChef.sol";

import "../cvaults/bsc/bank/BankBNB.sol";
import "../cvaults/bsc/CVaultBSCFlip.sol";
import "../vaults/legacy/BunnyPool.sol";
import "../vaults/legacy/BunnyBNBPool.sol";
import "./calculator/PriceCalculatorBSC.sol";

interface IVaultVenus {
    function getUtilizationInfo() external view returns (uint, uint);
}

contract DashboardBSC is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    PriceCalculatorBSC public constant priceCalculator = PriceCalculatorBSC(0x542c06a5dc3f27e0fbDc9FB7BC6748f26d54dDb0);
    CVaultBSCFlip public constant cvaultBSCFlip = CVaultBSCFlip(0x231AeFF3f80657D4bCf92BAD96B350c322b84d4F);

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address public constant BUNNY_BNB = 0x7Bb89460599Dbf32ee3Aa50798BBcEae2A5F7f6a;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant VaultCakeToCake = 0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD;
    address public constant WETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;

    IBunnyChef private constant bunnyChef = IBunnyChef(0x40e31876c4322bd033BAb028474665B12c4d04CE);

    BunnyPool private constant bunnyPool = BunnyPool(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);
    BunnyBNBPool private constant bunnyBnbPool = BunnyBNBPool(0xc80eA568010Bca1Ad659d1937E17834972d66e0D);

    /* ========== STATE VARIABLES ========== */

    mapping(address => PoolConstant.PoolTypes) public poolTypes;
    mapping(address => uint) public pancakePoolIds;
    mapping(address => bool) public perfExemptions;


    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
        setupPools();
    }

    function setupPools() public onlyOwner {
        // bunny legacy
        setPoolType(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D, PoolConstant.PoolTypes.BunnyStake);
        setPancakePoolId(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D, 9999);
        setPerfExemption(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D, true);

        // bunny-bnb legacy
        setPoolType(0xc80eA568010Bca1Ad659d1937E17834972d66e0D, PoolConstant.PoolTypes.BunnyFlip);
        setPancakePoolId(0xc80eA568010Bca1Ad659d1937E17834972d66e0D, 9999);
        setPerfExemption(0xc80eA568010Bca1Ad659d1937E17834972d66e0D, true);

        // bunny boost
        setPoolType(0xb037581cF0cE10b04C4735443d95e0C93db5d940, PoolConstant.PoolTypes.Bunny);
        setPancakePoolId(0xb037581cF0cE10b04C4735443d95e0C93db5d940, 9999);
        setPerfExemption(0xb037581cF0cE10b04C4735443d95e0C93db5d940, true);

        // bunny-bnb boost
        setPoolType(0x69FF781Cf86d42af9Bf93c06B8bE0F16a2905cBC, PoolConstant.PoolTypes.BunnyBNB);
        setPancakePoolId(0x69FF781Cf86d42af9Bf93c06B8bE0F16a2905cBC, 9999);

        // cake
        setPoolType(0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD, PoolConstant.PoolTypes.CakeStake);
        setPancakePoolId(0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD, 0);

        // cake-bnb flip
        setPoolType(0x7eaaEaF2aB59C2c85a17BEB15B110F81b192e98a, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0x7eaaEaF2aB59C2c85a17BEB15B110F81b192e98a, 1);

        // cake-bnb maxi
        setPoolType(0x3f139386406b0924eF115BAFF71D0d30CC090Bd5, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0x3f139386406b0924eF115BAFF71D0d30CC090Bd5, 1);

        // busd-bnb flip
        setPoolType(0x1b6e3d394f1D809769407DEA84711cF57e507B99, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0x1b6e3d394f1D809769407DEA84711cF57e507B99, 2);

        // busd-bnb maxi
        setPoolType(0x92a0f75a0f07C90a7EcB65eDD549Fa6a45a4975C, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0x92a0f75a0f07C90a7EcB65eDD549Fa6a45a4975C, 2);

        // usdt-bnb flip
        setPoolType(0xC1aAE51746bEA1a1Ec6f17A4f75b422F8a656ee6, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0xC1aAE51746bEA1a1Ec6f17A4f75b422F8a656ee6, 17);

        // usdt-bnb maxi
        setPoolType(0xE07BdaAc4573a00208D148bD5b3e5d2Ae4Ebd0Cc, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0xE07BdaAc4573a00208D148bD5b3e5d2Ae4Ebd0Cc, 17);

        // vai-busd flip
        setPoolType(0xa59EFEf41040e258191a4096DC202583765a43E7, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0xa59EFEf41040e258191a4096DC202583765a43E7, 41);

        // vai-busd maxi
        setPoolType(0xa5B8cdd3787832AdEdFe5a04bF4A307051538FF2, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0xa5B8cdd3787832AdEdFe5a04bF4A307051538FF2, 41);

        // usdt-busd flip
        setPoolType(0xC0314BbE19D4D5b048D3A3B974f0cA1B2cEE5eF3, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0xC0314BbE19D4D5b048D3A3B974f0cA1B2cEE5eF3, 11);

        // usdt-busd maxi
        setPoolType(0x866FD0028eb7fc7eeD02deF330B05aB503e199d4, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0x866FD0028eb7fc7eeD02deF330B05aB503e199d4, 11);

        // btcb-bnb flip
        setPoolType(0x0137d886e832842a3B11c568d5992Ae73f7A792e, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0x0137d886e832842a3B11c568d5992Ae73f7A792e, 15);

        // btcb-bnb maxi
        setPoolType(0xCBd4472cbeB7229278F841b2a81F1c0DF1AD0058, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0xCBd4472cbeB7229278F841b2a81F1c0DF1AD0058, 15);

        // eth-bnb flip
        setPoolType(0xE02BCFa3D0072AD2F52eD917a7b125e257c26032, PoolConstant.PoolTypes.FlipToFlip);
        setPancakePoolId(0xE02BCFa3D0072AD2F52eD917a7b125e257c26032, 14);

        // eth-bnb maxi
        setPoolType(0x41dF17D1De8D4E43d5493eb96e01100908FCcc4f, PoolConstant.PoolTypes.FlipToCake);
        setPancakePoolId(0x41dF17D1De8D4E43d5493eb96e01100908FCcc4f, 14);
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

    /* ========== Compound Calculation ========== */

    function borrowCompound(address pool) public view returns (uint) {
        if (poolTypes[pool] != PoolConstant.PoolTypes.Liquidity) {
            return 0;
        }

        BankBNB bankBNB = BankBNB(payable(pool));
        return bankBNB.config().getInterestRate(bankBNB.glbDebtVal(), bankBNB.totalLocked()).mul(1 days).add(1e18).power(365).sub(1e18);
    }

    /* ========== Utilization Calculation ========== */

    function utilizationOfPool(address pool) public view returns (uint liquidity, uint utilized) {
        if (poolTypes[pool] == PoolConstant.PoolTypes.Liquidity) {
            return BankBNB(payable(pool)).getUtilizationInfo();
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.Venus) {
            return IVaultVenus(payable(pool)).getUtilizationInfo();
        }
        return (0, 0);
    }

    /* ========== Portfolio Calculation ========== */

    function stakingTokenValueInUSD(address pool, address account) internal view returns (uint tokenInUSD) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];

        address stakingToken;
        if (poolType == PoolConstant.PoolTypes.BunnyStake) {
            stakingToken = BUNNY;
        } else if (poolType == PoolConstant.PoolTypes.BunnyFlip) {
            stakingToken = BUNNY_BNB;
        } else {
            stakingToken = IStrategy(pool).stakingToken();
        }

        if (stakingToken == address(0)) return 0;
        (, tokenInUSD) = priceCalculator.valueOfAsset(stakingToken, IStrategy(pool).principalOf(account));
    }

    function portfolioOfPoolInUSD(address pool, address account) public view returns (uint) {
        uint tokenInUSD = stakingTokenValueInUSD(pool, account);
        (, uint profitInBNB) = calculateProfit(pool, account);
        uint profitInBUNNY = 0;

        if (!perfExemptions[pool]) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.minter() != address(0)) {
                profitInBNB = profitInBNB.mul(70).div(100);
                profitInBUNNY = IBunnyMinter(strategy.minter()).amountBunnyToMint(profitInBNB.mul(30).div(100));
            }

            if ((poolTypes[pool] == PoolConstant.PoolTypes.Bunny || poolTypes[pool] == PoolConstant.PoolTypes.BunnyBNB)
                && strategy.bunnyChef() != address(0)) {
                profitInBUNNY = profitInBUNNY.add(bunnyChef.pendingBunny(pool, account));
            }
        }

        (, uint profitBNBInUSD) = priceCalculator.valueOfAsset(WBNB, profitInBNB);
        (, uint profitBUNNYInUSD) = priceCalculator.valueOfAsset(BUNNY, profitInBUNNY);
        return tokenInUSD.add(profitBNBInUSD).add(profitBUNNYInUSD);
    }

    /* ========== Profit Calculation ========== */

    function calculateProfit(address pool, address account) public view returns (uint profit, uint profitInBNB) {
        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (profit,) = priceCalculator.valueOfAsset(address(bunnyPool.rewardsToken()), bunnyPool.earned(account));
            // bnb
            profitInBNB = profit;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            IBunnyMinter minter = bunnyBnbPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                profit = minter.amountBunnyToMintForBunnyBNB(bunnyBnbPool.balanceOf(account), block.timestamp.sub(bunnyBnbPool.depositedAt(account)));
                // bunny
                (profitInBNB,) = priceCalculator.valueOfAsset(BUNNY, profit);
            }
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.Liquidity) {
            IStrategy strategy = IStrategy(pool);
            (profit,) = priceCalculator.valueOfAsset(strategy.stakingToken(), strategy.earned(account));
            // bnb
            profitInBNB = profit;
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.Bunny) {
            profit = bunnyChef.pendingBunny(pool, account);
            // bunny
            (profitInBNB,) = priceCalculator.valueOfAsset(BUNNY, profit);
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.CakeStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            profit = strategy.earned(account);
            (profitInBNB,) = priceCalculator.valueOfAsset(strategy.stakingToken(), profit);
            // underlying
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToCake || poolTypes[pool] == PoolConstant.PoolTypes.BunnyBNB) {
            IStrategy strategy = IStrategy(pool);
            profit = strategy.earned(account).mul(IStrategy(strategy.rewardsToken()).priceShare()).div(1e18);
            // cake
            (profitInBNB,) = priceCalculator.valueOfAsset(CAKE, profit);
        }
        return (0, 0);
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

            PoolConstant.PoolTypes poolType = poolTypeOf(pool);
            if (poolType == PoolConstant.PoolTypes.Bunny || poolType == PoolConstant.PoolTypes.BunnyBNB ||
                poolType == PoolConstant.PoolTypes.Venus) {
                if (strategy.bunnyChef() != address(0)) {
                    bunny = bunny.add(bunnyChef.pendingBunny(pool, account));
                }
            }
        }
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint tvl) {
        if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyStake) {
            (, tvl) = priceCalculator.valueOfAsset(address(bunnyPool.stakingToken()), bunnyPool.balance());
        }
        else if (poolTypes[pool] == PoolConstant.PoolTypes.BunnyFlip) {
            (, tvl) = priceCalculator.valueOfAsset(address(bunnyBnbPool.token()), bunnyBnbPool.balance());
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
        poolInfo.apyBorrow = borrowCompound(pool);
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

    /* ========== Portfolio Calculation ========== */

    function portfolioOf(address account, address[] memory pools) public view returns (uint deposits) {
        deposits = 0;
        for (uint i = 0; i < pools.length; i++) {
            deposits = deposits.add(portfolioOfPoolInUSD(pools[i], account));
        }
    }

    /* ========== PREDICT FUNCTIONS ========== */

    function amountsOfCVaultUpdateLeverage(address lp, address _account, uint collateral, uint128 leverage) public view returns (uint bnbAmountIn, uint flipAmountIn, uint bnbAmountOut, uint flipAmountOut) {
        (uint flipPriceInBNB,) = priceCalculator.valueOfAsset(cvaultBSCFlip.flipOf(lp), 1e18);
        (uint bnbIn, uint bnbOut, uint cakeOut) = cvaultBSCFlip.calculateAmountsInOut(lp, _account, collateral, leverage);
        if (bnbIn > 0) {
            bnbAmountIn = bnbIn;
            flipAmountIn = bnbIn.mul(1e18).div(flipPriceInBNB);
            bnbAmountOut = 0;
            flipAmountOut = 0;
        } else {
            IBankBNB bankBNB = cvaultBSCFlip.bankBNB();
            uint debtShare = bankBNB.debtShareOf(lp, _account);
            (uint cakeValueInBNB,) = priceCalculator.valueOfAsset(CAKE, cakeOut);

            bnbAmountIn = 0;
            flipAmountIn = 0;
            flipAmountOut = bnbOut.add(cakeValueInBNB).mul(1e18).div(flipPriceInBNB);
            bnbAmountOut = bankBNB.debtShareToVal(Math.min(bankBNB.debtValToShare(bnbOut.add(cakeValueInBNB)), debtShare));
        }
    }

    function amountsOfCVaultRemoveLiquidity(address lp, address _account, uint collateral, uint128 leverage) public view returns (uint bnbAmountOut, uint tokenAmountOut) {
        IPancakePair pair = IPancakePair(cvaultBSCFlip.flipOf(lp));
        address token = pair.token0() == WBNB ? pair.token1() : pair.token0();

        (uint tokenPriceInBNB,) = priceCalculator.valueOfAsset(token, 1e18);
        (, uint bnbOut, uint cakeOut) = cvaultBSCFlip.calculateAmountsInOut(lp, _account, collateral, leverage);

        (uint cakeInBNB,) = priceCalculator.valueOfAsset(CAKE, cakeOut);
        return (bnbOut.div(2).add(cakeInBNB), bnbOut.div(2).mul(1e18).div(tokenPriceInBNB));
    }

    function collateralRatio(address lp, uint lpAmount, uint flipAmount, uint debt) public view returns (uint) {
        return cvaultBSCFlip.collateralRatio(lp, lpAmount, flipAmount, debt);
    }

    function profitAndLoss(address lp, address _account) public view returns (uint profit, uint loss) {
        profit = 0;
        loss = 0;

        (, uint bnbOut, uint cakeOut) = cvaultBSCFlip.calculateAmountsInOut(lp, _account, 0, uint128(0));
        (uint cakeInBNB,) = priceCalculator.valueOfAsset(CAKE, cakeOut);

        uint balance = bnbOut.add(cakeInBNB);
        IBankBNB bankBNB = cvaultBSCFlip.bankBNB();
        uint debtShare = bankBNB.debtShareOf(lp, _account);
        (uint valueInBNB,) = priceCalculator.valueOfAsset(WETH, 1e18);

        if (balance > debtShare) {
            profit = balance.sub(debtShare).mul(1e18).div(valueInBNB);
        } else {
            loss = debtShare.sub(balance).mul(1e18).div(valueInBNB);
        }
    }
}
