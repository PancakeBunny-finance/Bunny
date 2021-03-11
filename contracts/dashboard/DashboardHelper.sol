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
import "@openzeppelin/contracts/math/Math.sol";

import "../library/SafeDecimal.sol";

import "../cvaults/bsc/venus/IVToken.sol";
import "../cvaults/bsc/venus/IVenusDistribution.sol";
import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IDashboard.sol";
import "../cvaults/interface/IBankBNB.sol";
import "../cvaults/interface/ICPool.sol";

import "../cvaults/bsc/CVaultBSCFlipStorage.sol";

contract DashboardHelper is Ownable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    uint private constant BLOCK_PER_DAY = 28800;

    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

    IVToken private constant vBNB = IVToken(0xA07c5b74C9B40447a954e1466938b865b6BBea36);
    IVenusDistribution private constant vComptroller = IVenusDistribution(0xfD36E2c2a6789Db23113685031d7F16329158384);
    AggregatorV3Interface private constant bnbPriceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);

    uint private borrowDepth = 3;
    IDashboard private dashboardBSC;

    /* ========== INITIALIZER ========== */

    constructor(address _dashboadBSC, uint _borrowDepth) public {
        dashboardBSC = IDashboard(_dashboadBSC);
        borrowDepth = _borrowDepth;
    }

    /* ========== Venus APY Calculation ========== */

    function apyOfVenus() public view returns(
        uint borrowApy,
        uint supplyApy
    ) {
        borrowApy = vBNB.borrowRatePerBlock().mul(BLOCK_PER_DAY).add(1e18).power(365).sub(1e18);
        supplyApy = vBNB.supplyRatePerBlock().mul(BLOCK_PER_DAY).add(1e18).power(365).sub(1e18);
    }

    // Distributon APY
    // https://github.com/VenusProtocol/venus-protocol/issues/15#issuecomment-741292855
    function apyOfDistribution(uint _priceVenusBNB) public view returns(
        uint distributionBorrowAPY,
        uint distributionSupplyAPY
    ) {
        uint totalSupply = vBNB.totalSupply().mul(vBNB.exchangeRateStored()).div(1e18);
        uint venusPerDay = vComptroller.venusSpeeds(address(vBNB)).mul(BLOCK_PER_DAY);

        distributionBorrowAPY = (uint(_priceVenusBNB.mul(venusPerDay))/uint(vBNB.totalBorrows())).add(1e18).power(365).sub(1e18);
        distributionSupplyAPY = (uint(_priceVenusBNB.mul(venusPerDay))/uint(totalSupply)).add(1e18).power(365).sub(1e18);
    }

    function calculateAPY(uint amount, uint venusBorrow, uint distributionBorrow, uint supplyAPY) public view returns(uint apyPool) {
        uint profit = 0;

        bool isNegative = venusBorrow > distributionBorrow;
        uint borrow;
        if (isNegative) {
            borrow = venusBorrow.sub(distributionBorrow);
        } else {
            borrow = distributionBorrow.sub(venusBorrow);
        }
        uint ratio = 585e15;

        uint calculatedAmount = amount.mul(supplyAPY).div(1e18);
        profit = profit.add(calculatedAmount);
        calculatedAmount = amount.mul(ratio).div(1e18);

        for (uint i = 0; i < borrowDepth; i++) {
            profit = profit.add(calculatedAmount.mul(supplyAPY).div(1e18));
            if (isNegative) {
                profit = profit.sub(calculatedAmount.mul(borrow).div(1e18));
            } else {
                profit = profit.add(calculatedAmount.mul(borrow).div(1e18));
            }
            calculatedAmount = calculatedAmount.mul(ratio).div(1e18);
        }

        apyPool = profit.mul(1e18).div(amount);
    }

    /* ========== Predict function ========== */

    function predict(address lp, address flip, address _account, uint collateralETH, uint collateralBSC, uint leverage, uint debtBNB) public view returns(
        uint newCollateralBSC,
        uint newDebtBNB
    ) {
        IBankBNB bankBNB = IBankBNB(dashboardBSC.bankBNBAddress());

        uint currentDebt = bankBNB.debtValOf(lp, _account);
        uint targetDebt = _calculateTargetDebt(lp, uint128(leverage), collateralETH);
        if (currentDebt <= targetDebt) {
            (uint bscFlip, uint debt) = _addLiquidity(flip, targetDebt.sub(currentDebt));
            newCollateralBSC = collateralBSC.add(bscFlip);
            newDebtBNB = debtBNB.add(debt);
        } else {
            uint flipAmount = convertToFlipAmount(address(WBNB), flip, currentDebt.sub(targetDebt));
            (newCollateralBSC, newDebtBNB) = _removeLiquidity(lp, _account, flipAmount, collateralBSC, debtBNB);
        }
    }

    function withdrawAmountToBscTokens(address lp, address _account, uint leverage, uint amount) public view returns(uint bnbAmount, uint pairAmount, uint bnbOfPair) {
        IBankBNB bankBNB = IBankBNB(dashboardBSC.bankBNBAddress());
        CVaultBSCFlipStorage flip = CVaultBSCFlipStorage(dashboardBSC.bscFlipAddress());
        address flipAddr = flip.flipOf(lp);

        uint currentDebt = bankBNB.debtValOf(lp, _account);
        uint targetDebt = _calculateTargetDebt(lp, uint128(leverage), amount);
        if (currentDebt > targetDebt) {
            uint flipAmount = convertToFlipAmount(address(WBNB), flipAddr, currentDebt.sub(targetDebt));
            (bnbAmount, pairAmount, bnbOfPair) = _withdrawAmountToBscTokens(lp, _account, flipAmount);
        }
    }

    function collateralRatio(address lp, uint lpAmount, address flip, uint flipAmount, uint debt) public view returns(uint) {
        ICVaultRelayer relayer = ICVaultRelayer(dashboardBSC.relayerAddress());
        return relayer.collateralRatioOnETH(lp, lpAmount, flip, flipAmount, debt);
    }

    /* ========== Convert amount ========== */

    // only BNB Pairs TODO all pairs
    function convertToBNBAmount(address flip, uint amount) public view returns(uint) {
        if (keccak256(abi.encodePacked(IPancakePair(flip).symbol())) == keccak256("Cake-LP")) {
            IPancakePair pair = IPancakePair(flip);
            (uint reserve0, uint reserve1,) = pair.getReserves();
            if (pair.token0() == address(WBNB)) {
                return amount.mul(reserve1).div(reserve0);
            } else {
                return amount.mul(reserve0).div(reserve1);
            }
        } else {
            return amount;
        }
    }

    function convertToFlipAmount(address tokenIn, address flip, uint amount) public view returns(uint) {
        if (keccak256(abi.encodePacked(IPancakePair(flip).symbol())) == keccak256("Cake-LP")) {
            IPancakePair pair = IPancakePair(flip);
            if (tokenIn == address(WBNB) || tokenIn == address(0)) {
                return amount.div(2).mul(pair.totalSupply()).div(WBNB.balanceOf(flip));
            } else {
                // TODO
                return 0;
            }
        } else {
            return amount;
        }
    }

    /* ========== Calculation ========== */

    function _calculateTargetDebt(address lp, uint128 leverage, uint collateral) private view returns(uint) {
        ICVaultRelayer relayer = ICVaultRelayer(dashboardBSC.relayerAddress());

        uint value = relayer.valueOfAsset(lp, collateral);
        return value.mul(leverage).div(dashboardBSC.priceOfBNB());
    }

    function _addLiquidity(address flip, uint debtDiff) private view returns(uint bscFlip, uint debtBNB) {
        IBankBNB bankBNB = IBankBNB(dashboardBSC.bankBNBAddress());
        (uint totalSupply, uint utilized) = bankBNB.getUtilizationInfo();
        uint amount = Math.min(debtDiff, totalSupply.sub(utilized));
        if (amount > 0) {
            bscFlip = convertToFlipAmount(address(WBNB), flip, amount);
            debtBNB = amount;
        }
    }

    function _removeLiquidity(address lp, address _account, uint amount, uint collateralBSC, uint debtBNB) private view returns(uint newCollateralBSC, uint newDebtBNB) {
        if (amount < collateralBSC) {
            newCollateralBSC = collateralBSC.sub(amount);
        } else {
            newCollateralBSC = 0;
        }

        (uint bnbAmount, , uint bnbOfPair) = _withdrawAmountToBscTokens(lp, _account, amount);
        // _repay
        uint repayDebtBNB = _repay(lp, _account, bnbAmount.add(bnbOfPair));

        if (repayDebtBNB < debtBNB) {
            newDebtBNB = debtBNB.sub(repayDebtBNB);
        } else {
            newDebtBNB = 0;
        }
    }

    function _repay(address lp, address _account, uint amount) private view returns(uint) {
        IBankBNB bankBNB = IBankBNB(dashboardBSC.bankBNBAddress());
        uint debtShare = Math.min(bankBNB.debtValToShare(amount), bankBNB.debtShareOf(lp, _account));
        if (debtShare > 0) {
            return debtShare;
        } else {
            return 0;
        }
    }

    function _withdrawAmountToBscTokens(address lp, address account, uint amount) private view returns(uint bnbAmount, uint pairAmount, uint bnbOfpair) {
        CVaultBSCFlipStorage flip = CVaultBSCFlipStorage(dashboardBSC.bscFlipAddress());
        address flipAddr = flip.flipOf(lp);

        if (keccak256(abi.encodePacked(IPancakePair(flipAddr).symbol())) == keccak256("Cake-LP")) {
            (uint _bnbBalance,) = dashboardBSC.valueOfAsset(flipAddr, amount);
            bnbAmount = _bnbBalance.div(2);

            bnbOfpair = bnbAmount;
            pairAmount = convertToBNBAmount(flipAddr, bnbAmount);

            ICPool cpool = ICPool(flip.cpoolOf(lp));
            uint rewardBalance = cpool.rewards(account);    // reward
            (uint _bnbOfReward,) = dashboardBSC.valueOfAsset(address(CAKE), rewardBalance);
            bnbAmount = bnbAmount.add(_bnbOfReward);
        } else {
            (bnbAmount, ) = dashboardBSC.valueOfAsset(lp, amount);
            pairAmount = 0;
            bnbOfpair = bnbAmount;
        }
    }
}
