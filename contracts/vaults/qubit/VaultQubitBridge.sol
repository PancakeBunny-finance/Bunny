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
* SOFTWARE.
*/

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../../library/SafeToken.sol";
import "../../library/WhitelistUpgradeable.sol";

import "../../interfaces/IPancakeRouter02.sol";
import "../../interfaces/qubit/IQDistributor.sol";
import "../../interfaces/qubit/IQToken.sol";
import "../../interfaces/qubit/IVaultQubitBridge.sol";
import "../../interfaces/qubit/IQore.sol";
import "../../interfaces/qubit/IQubitLocker.sol";
import "../../interfaces/qubit/IRewardDistributed.sol";
import "../../interfaces/IWETH.sol";

import "../../interfaces/IPriceCalculator.sol";

contract VaultQubitBridge is WhitelistUpgradeable, IVaultQubitBridge {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    IPancakeRouter02 private constant PANCAKE_ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    IQDistributor private constant QUBIT_DISTRIBUTOR = IQDistributor(0x67B806ab830801348ce719E0705cC2f2718117a1);
    IQubitLocker private constant QUBIT_LOCKER = IQubitLocker(0xB8243be1D145a528687479723B394485cE3cE773);
    IQore private constant QORE = IQore(0xF70314eb9c7Fe7D88E6af5aa7F898b3A162dcd48);

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    IBEP20 private constant QBT = IBEP20(0x17B7163cf1Dbd286E262ddc68b553D899B93f526);

    uint public constant LOCKING_DURATION = 2 * 365 days;

    /* ========== STATE VARIABLES ========== */

    IRewardDistributed public qubitPool;
    IRewardDistributed public vaultFlipToQBT;

    MarketInfo[] private _marketList;
    mapping(address => MarketInfo) markets;

    /* ========== EVENTS ========== */

    event Recovered(address token, uint amount);

    /* ========== MODIFIERS ========== */

    modifier updateAvailable(address vault) {
        MarketInfo storage market = markets[vault];
        uint tokenBalanceBefore = market.token != WBNB ? IBEP20(market.token).balanceOf(address(this)) : address(this).balance;
        uint qTokenAmountBefore = IQToken(market.qToken).balanceOf(address(this));
        _;

        uint tokenBalance = market.token != WBNB ? IBEP20(market.token).balanceOf(address(this)) : address(this).balance;
        uint qTokenAmount = IQToken(market.qToken).balanceOf(address(this));

        market.available = market.available.add(tokenBalance).sub(tokenBalanceBefore);
        market.qTokenAmount = market.qTokenAmount.add(qTokenAmount).sub(qTokenAmountBefore);
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __WhitelistUpgradeable_init();

        QBT.safeApprove(address(PANCAKE_ROUTER), uint(-1));
        QBT.safeApprove(address(QUBIT_LOCKER), uint(-1));

    }

    /* ========== VIEW FUNCTIONS ========== */

    function infoOf(address vault) public view override returns (MarketInfo memory) {
        return markets[vault];
    }

    function availableOf(address vault) public view override returns (uint) {
        return markets[vault].available;
    }

    function snapshotOf(address vault) public view override returns (uint vaultSupply, uint vaultBorrow) {
        MarketInfo memory market = markets[vault];
        vaultSupply = IQToken(market.qToken).underlyingBalanceOf(address(this));
        vaultBorrow = IQToken(market.qToken).borrowBalanceOf(address(this));
    }

    function liquidityOf(address vault, uint collateralRatioLimit) public view returns (uint vaultLiquidity, uint marketLiquidity) {
        MarketInfo memory market = markets[vault];
        if (collateralRatioLimit == 0) {
            vaultLiquidity = 0;
            marketLiquidity = 0;
        } else {
            (uint vaultSupply, uint vaultBorrow) = snapshotOf(vault);
            vaultLiquidity = vaultSupply > vaultBorrow.mul(1e18).div(collateralRatioLimit)
            ? vaultSupply.sub(vaultBorrow.mul(1e18).div(collateralRatioLimit)) : 0;

            uint marketTotalBorrow = IQToken(market.qToken).totalBorrow();
            uint marketTotalSupply = (IQToken(market.qToken).totalSupply()).mul(IQToken(market.qToken).exchangeRate()).div(1e18);
            marketLiquidity = marketTotalSupply > marketTotalBorrow ? marketTotalSupply.sub(marketTotalBorrow) : 0;
        }
    }

    function borrowableOf(address vault, uint collateralRatioLimit) public view override returns (uint) {
        (uint vaultLiquidity, uint marketLiquidity) = liquidityOf(vault, collateralRatioLimit);
        return Math.min(vaultLiquidity, marketLiquidity).mul(collateralRatioLimit).div(1e18);
    }

    function redeemableOf(address vault, uint collateralRatioLimit) public view override returns (uint) {
        (uint vaultLiquidity, uint marketLiquidity) = liquidityOf(vault, collateralRatioLimit);
        return Math.min(vaultLiquidity, marketLiquidity);
    }

    function leverageRoundOf(address vault, uint round) external view override returns (uint) {
        MarketInfo memory market = markets[vault];
        QConstant.DistributionAPY memory apyInfo = QUBIT_DISTRIBUTOR.apyDistributionOf(market.qToken, address(this));
        uint apySupply = IQToken(market.qToken).supplyRatePerSec().mul(365 days);
        uint apyBorrow = IQToken(market.qToken).borrowRatePerSec().mul(365 days);
        uint apyDistribution = apyInfo.apyAccountSupplyQBT.add(apyInfo.apyAccountBorrowQBT);
        return apyBorrow > apyDistribution && apySupply.add(apyDistribution) <= apyBorrow + 3e15 ? 0 : round;
    }

    function getBoostRatio(address vault) public view override returns (uint boostRatio) {
        MarketInfo memory market = markets[vault];
        (uint supplyBoostRatio, uint borrowBoostRatio) = QORE.boostedRatioOf(market.qToken, address(this));
        (uint vaultSupply, uint vaultBorrow) = snapshotOf(vault);
        boostRatio = vaultSupply.add(vaultBorrow) == 0 ? 1e18 : Math.max(supplyBoostRatio.mul(vaultSupply).add(borrowBoostRatio.mul(vaultBorrow)).div(vaultSupply.add(vaultBorrow)), 1e18);
    }

    /* ========== RESTRICTED FUNCTIONS - SAV ========== */

    function addVault(address vault, address token, address qToken, uint rewardsDuration) public onlyOwner {
        require(markets[vault].token == address(0), "VaultQubitBridge: vault is already set");
        require(vault != address(0) && token != address(0) && qToken != address(0), "VaultQubitBridge: invalid address");

        MarketInfo memory market = MarketInfo(token, qToken, 0, 0, 0, rewardsDuration);
        _marketList.push(market);
        markets[vault] = market;

        // QBT is already approved at initialization
        if (token != address(QBT)) {
            IBEP20(token).safeApprove(address(PANCAKE_ROUTER), uint(-1));
        }
        IBEP20(token).safeApprove(qToken, uint(-1));
        QBT.safeApprove(vault, uint(-1));

        address[] memory qubitMarkets = new address[](1);
        qubitMarkets[0] = qToken;
        QORE.enterMarkets(qubitMarkets);
    }

    function updateRewardsDuration(uint _rewardsDuration) external override onlyWhitelisted {
        MarketInfo storage market = markets[msg.sender];
        market.rewardsDuration = _rewardsDuration;
    }

    function deposit(address vault, uint uAmount) external payable override onlyWhitelisted {
        require(markets[vault].token != address(0), "VaultQubitBridge: the vault is not set!");

        MarketInfo storage market = markets[vault];
        market.available = market.available.add(msg.value > 0 ? msg.value : uAmount);
        market.principal = market.principal.add(msg.value > 0 ? msg.value : uAmount);
    }

    function withdraw(uint amount, address to) external override onlyWhitelisted {
        require(markets[msg.sender].token != address(0), "VaultQubitBridge: the vault is not set!");
        require(amount <= markets[msg.sender].available, "VaultQubitBridge: invalid withdraw amount");

        MarketInfo storage market = markets[msg.sender];
        market.available = market.available.sub(amount);
        market.principal = market.principal.sub(amount);
        if (market.token == WBNB) {
            SafeToken.safeTransferETH(to, amount);
        } else {
            IBEP20(market.token).safeTransfer(to, amount);
        }
    }

    function harvest() public override updateAvailable(msg.sender) onlyWhitelisted returns (uint) {
        MarketInfo memory market = markets[msg.sender];

        uint _qbtBefore = QBT.balanceOf(address(this));
        QORE.claimQubit(market.qToken);
        uint claimed = QBT.balanceOf(address(this)).sub(_qbtBefore);
        if (claimed == 0) return 0;

        // 1.0 <= boostRatio <= 2.5
        uint boostRatio = getBoostRatio(msg.sender);

        // bQBT reward = claimed * (boostRatio - 1) * 0.1
        uint rewardForBunnyQBT = claimed.mul(boostRatio.sub(1e18)).div(1e18).mul(10).div(100);
        claimed = claimed.sub(rewardForBunnyQBT);

        if (address(qubitPool) != address(0)) {
            if (address(vaultFlipToQBT) != address(0)) {
                uint rewardForVaultFlipToQBT = rewardForBunnyQBT.div(2);
                QBT.transfer(address(vaultFlipToQBT), rewardForVaultFlipToQBT);
                vaultFlipToQBT.notifyRewardAmount(rewardForVaultFlipToQBT);
                rewardForBunnyQBT = rewardForBunnyQBT.sub(rewardForVaultFlipToQBT);
            }

            QBT.transfer(address(qubitPool), rewardForBunnyQBT);
            qubitPool.notifyRewardAmount(rewardForBunnyQBT);
        }

        _qbtBefore = QBT.balanceOf(address(this));
        _swapShortage(msg.sender, claimed);
        claimed = claimed.sub(_qbtBefore.sub(QBT.balanceOf(address(this))));
        QBT.transfer(msg.sender, claimed);
        return claimed;
    }

    /* ========== RESTRICTED FUNCTIONS - bQBT ========== */

    function setQubitPool(address _qubitPool) external onlyOwner {
        require(address(qubitPool) == address(0), "VaultQubitBridge: qubitPool is already set");
        qubitPool = IRewardDistributed(_qubitPool);
    }

    function setVaultFlipToQBT(address _vaultFlipToQBT) external onlyOwner {
        require(_vaultFlipToQBT != address(0), "VaultQubitBridge: wrong address");
        vaultFlipToQBT = IRewardDistributed(_vaultFlipToQBT);
    }

    function lockup(uint _amount) external override onlyWhitelisted {
        uint _before = QBT.balanceOf(address(this));
        QBT.safeTransferFrom(msg.sender, address(this), _amount);
        uint amount = QBT.balanceOf(address(this)).sub(_before);

        if (amount > 0) {
            uint nextExpiry = block.timestamp + LOCKING_DURATION;

            // QLocker: if bridge deposit after expiry, withdraw and deposit again with new expiry
            // |--------------|expiry|-------|deposit|-------------|
            if (QUBIT_LOCKER.balanceOf(address(this)) > 0 && QUBIT_LOCKER.expiryOf(address(this)) < block.timestamp) {
                uint beforeQBTBalance = QBT.balanceOf(address(this));
                QUBIT_LOCKER.withdraw();
                uint withdrawAmount = QBT.balanceOf(address(this)).sub(beforeQBTBalance);
                amount = amount.add(withdrawAmount);
            }
            QUBIT_LOCKER.deposit(amount, nextExpiry);

            // QLocker: if expiry period is less than lockingDuration, extend expiry (guarantee minimum lockingDuration)
            // |                  |-------lockingDuration------|
            // |--------------|current|-------|expiry|------------->|extended expiry|------|
            uint timeElapsed = QUBIT_LOCKER.expiryOf(address(this)).sub(block.timestamp);
            if (timeElapsed < LOCKING_DURATION && QUBIT_LOCKER.expiryOf(address(this)) < nextExpiry.div(7 days).mul(7 days)) {
                QUBIT_LOCKER.extendLock(nextExpiry);
            }
        }
    }

    /* ========== QUBIT FUNCTIONS ========== */

    function supply(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        require(markets[msg.sender].token != address(0), "VaultQubitBridge: the vault is not set!");
        require(amount <= markets[msg.sender].available, "vaultQubitBridge: not enough available amount");
        MarketInfo memory market = markets[msg.sender];
        if (market.token == WBNB) {
            QORE.supply{ value: amount }(market.qToken, amount);
        } else {
            QORE.supply(market.qToken, amount);
        }
    }

    function redeemUnderlying(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        QORE.redeemUnderlying(market.qToken, amount);
    }

    function redeemAll() external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        QORE.redeemToken(market.qToken, market.qTokenAmount);
    }

    function borrow(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        QORE.borrow(market.qToken, amount);
    }

    function repayBorrow(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        if (market.token == WBNB) {
            QORE.repayBorrow{ value: amount }(market.qToken, amount);
        } else {
            QORE.repayBorrow(market.qToken, amount);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _swapShortage(address vault, uint amountIn) private {
        MarketInfo memory market = markets[vault];
        (uint vaultSupply, uint vaultBorrow) = snapshotOf(vault);
        uint vaultBalance = market.available.add(vaultSupply).sub(vaultBorrow);

        uint nextBorrowInterest = IQToken(market.qToken).borrowRatePerSec().mul(vaultBorrow).mul(market.rewardsDuration).mul(2).div(1e18);
        uint nextSupplyInterest = IQToken(market.qToken).supplyRatePerSec().mul(vaultSupply).mul(market.rewardsDuration).mul(2).div(1e18);
        uint nextInterest = nextBorrowInterest > nextSupplyInterest ? nextBorrowInterest.sub(nextSupplyInterest) : 0;

        if (market.principal < vaultBalance && vaultBalance.sub(market.principal) > nextInterest) {
            return;
        }

        uint shortage = market.principal.add(nextInterest).sub(vaultBalance);

        if (shortage > 0) {
            if (market.token == WBNB) {
                address[] memory path = new address[](2);
                path[0] = address(QBT);
                path[1] = WBNB;

                uint[] memory amounts = PANCAKE_ROUTER.getAmountsOut(amountIn, path); // get maximum amount from given amount of assets
                uint amountOut = Math.min(amounts[1], shortage);
                PANCAKE_ROUTER.swapTokensForExactETH(amountOut, amountIn, path, address(this), block.timestamp);
            } else {
                address[] memory path = new address[](3);
                path[0] = address(QBT);
                path[1] = WBNB;
                path[2] = market.token;

                uint[] memory amounts = PANCAKE_ROUTER.getAmountsOut(amountIn, path); // get maximum amount from given amount of asset
                uint amountOut = Math.min(amounts[2], shortage);
                PANCAKE_ROUTER.swapTokensForExactTokens(amountOut, amountIn, path, address(this), block.timestamp);
            }
        }
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address token, uint amount) external onlyOwner {
        // case0) WBNB salvage
        if (token == WBNB && IBEP20(WBNB).balanceOf(address(this)) >= amount) {
            IBEP20(token).safeTransfer(owner(), amount);
            emit Recovered(token, amount);
            return;
        }

        // case1) vault token - WBNB=>BNB
        for (uint i = 0; i < _marketList.length; i++) {
            MarketInfo memory market = _marketList[i];

            if (market.qToken == token) {
                revert("VaultQubitBridge: cannot recover");
            }

            if (market.token == token) {
                uint balance = token == WBNB ? address(this).balance : IBEP20(token).balanceOf(address(this));
                require(balance.sub(market.available) >= amount, "VaultQubitBridge: cannot recover");

                if (token == WBNB) {
                    SafeToken.safeTransferETH(owner(), amount);
                } else {
                    IBEP20(token).safeTransfer(owner(), amount);
                }

                emit Recovered(token, amount);
                return;
            }
        }

        // case2) not vault token
        IBEP20(token).safeTransfer(owner(), amount);
        emit Recovered(token, amount);
    }
}
