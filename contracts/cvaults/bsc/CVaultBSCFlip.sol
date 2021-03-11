// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../../library/PausableUpgradeable.sol";

import "../../interfaces/IPancakePair.sol";
import "../../interfaces/IStrategy.sol";
import "../interface/ICVaultBSCFlip.sol";
import "../interface/IBankBNB.sol";
import "../interface/IBankETH.sol";
import "../interface/ICPool.sol";
import "../../zap/IZap.sol";

import "./CVaultBSCFlipState.sol";
import "./CVaultBSCFlipStorage.sol";


contract CVaultBSCFlip is ICVaultBSCFlip, CVaultBSCFlipStorage {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    /* ========== STATE VARIABLES ========== */

    IBankBNB private _bankBNB;
    IBankETH private _bankETH;
    IZap private _zap;

    /* ========== EVENTS ========== */

    event Deposited(address indexed lp, address indexed account, uint128 indexed eventId, uint debtShare, uint flipBalance);
    event UpdateLeverage(address indexed lp, address indexed account, uint128 indexed eventId, uint debtShare, uint flipBalance);
    event WithdrawAll(address indexed lp, address indexed account, uint128 indexed eventId, uint profit, uint loss);
    event EmergencyExit(address indexed lp, address indexed account, uint128 indexed eventId, uint profit, uint loss);
    event Liquidate(address indexed lp, address indexed account, uint128 indexed eventId, uint profit, uint loss);

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __CVaultBSCFlipStorage_init();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setPool(address lp, address flip, address cpool) external onlyOwner {
        require(address(_zap) != address(0), "CVaultBSCFlip: zap is not set");
        _setPool(lp, flip, cpool);

        if (IBEP20(flip).allowance(address(this), address(_zap)) == 0) {
            IBEP20(flip).safeApprove(address(_zap), uint(-1));
        }

        if (IBEP20(flip).allowance(address(this), cpool) == 0) {
            IBEP20(flip).safeApprove(cpool, uint(-1));
        }
    }

    function setBankBNB(address newBankBNB) public onlyOwner {
        require(address(_bankBNB) == address(0), "CVaultBSCFlip: setBankBNB only once");
        _bankBNB = IBankBNB(newBankBNB);
    }

    function setBankETH(address newBankETH) external onlyOwner {
        _bankETH = IBankETH(newBankETH);
    }

    function setZap(address newZap) external onlyOwner {
        _zap = IZap(newZap);
    }

    function recoverToken(address token, uint amount) external onlyOwner {
        IBEP20(token).safeTransfer(owner(), amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function zap() public view returns(IZap) {
        return _zap;
    }

    function bankBNB() public override view returns(IBankBNB) {
        return _bankBNB;
    }

    function bankETH() public override view returns(IBankETH) {
        return _bankETH;
    }

    function getUtilizationInfo() public override view returns (uint liquidity, uint utilized) {
        return bankBNB().getUtilizationInfo();
    }

    /* ========== RELAYER FUNCTIONS ========== */

    function deposit(address lp, address _account, uint128 eventId, uint112 nonce, uint128 leverage, uint collateral) external override increaseNonceOnlyRelayer(lp, _account, nonce) validLeverage(leverage) returns (uint bscBNBDebtShare, uint bscFlipBalance) {
        convertState(lp, _account, State.Farming);
        _updateLiquidity(lp, _account, leverage, collateral);
        bscBNBDebtShare = bankBNB().debtShareOf(lp, _account);
        bscFlipBalance = IStrategy(cpoolOf(lp)).balanceOf(_account);
        emit Deposited(lp, _account, eventId, bscBNBDebtShare, bscFlipBalance);
    }

    function updateLeverage(address lp, address _account, uint128 eventId, uint112 nonce, uint128 leverage, uint collateral) external override increaseNonceOnlyRelayer(lp, _account, nonce) validLeverage(leverage) returns (uint bscBNBDebtShare, uint bscFlipBalance) {
        require(accountOf(lp, _account).state == State.Farming, "CVaultBSCFlip: state is not Farming");

        _updateLiquidity(lp, _account, leverage, collateral);
        bscBNBDebtShare = bankBNB().debtShareOf(lp, _account);
        bscFlipBalance = IStrategy(cpoolOf(lp)).balanceOf(_account);
        emit UpdateLeverage(lp, _account, eventId, bscBNBDebtShare, bscFlipBalance);
    }

    function withdrawAll(address lp, address _account, uint128 eventId, uint112 nonce) external override increaseNonceOnlyRelayer(lp, _account, nonce) returns(uint ethProfit, uint ethLoss) {
        convertState(lp, _account, State.Idle);

        _removeLiquidity(lp, _account, IStrategy(cpoolOf(lp)).balanceOf(_account));
        (ethProfit, ethLoss) = _handleProfitAndLoss(lp, _account);

        emit WithdrawAll(lp, _account, eventId, ethProfit, ethLoss);
    }

    function emergencyExit(address lp, address _account, uint128 eventId, uint112 nonce) external override increaseNonceOnlyRelayer(lp, _account, nonce) returns (uint ethProfit, uint ethLoss) {
        convertState(lp, _account, State.Idle);

        uint flipBalance = IStrategy(cpoolOf(lp)).balanceOf(_account);
        _removeLiquidity(lp, _account, flipBalance);
        (ethProfit, ethLoss) = _handleProfitAndLoss(lp, _account);

        emit EmergencyExit(lp, _account, eventId, ethProfit, ethLoss);
    }

    function liquidate(address lp, address _account, uint128 eventId, uint112 nonce) external override increaseNonceOnlyRelayer(lp, _account, nonce) returns (uint ethProfit, uint ethLoss) {
        convertState(lp, _account, State.Idle);

        _removeLiquidity(lp, _account, IStrategy(cpoolOf(lp)).balanceOf(_account));
        (ethProfit, ethLoss) = _handleProfitAndLoss(lp, _account);
        emit Liquidate(lp, _account, eventId, ethProfit, ethLoss);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _updateLiquidity(address lp, address _account, uint128 leverage, uint collateral) private {
        uint targetDebtInBNB = _calculateTargetDebt(lp, collateral, leverage);
        uint currentDebtValue = bankBNB().accruedDebtValOf(lp, _account);

        if (currentDebtValue <= targetDebtInBNB) {
            uint borrowed = _borrow(lp, _account, targetDebtInBNB.sub(currentDebtValue));
            if (borrowed > 0) {
                _addLiquidity(lp, _account, borrowed);
            }
        } else {
            _removeLiquidity(lp, _account, _calculateFlipAmountWithBNB(flipOf(lp), currentDebtValue.sub(targetDebtInBNB)));
            _repay(lp, _account, address(this).balance);
        }
    }

    function _addLiquidity(address lp, address _account, uint value) private {
        address flip = flipOf(lp);
        _zap.zapIn{ value: value }(flip);
        ICPool(cpoolOf(lp)).deposit(_account, IBEP20(flip).balanceOf(address(this)));
    }

    function _removeLiquidity(address lp, address _account, uint amount) private {
        if (amount == 0) return;

        ICPool cpool = ICPool(cpoolOf(lp));
        cpool.withdraw(_account, amount);
        cpool.getReward(_account);

        _zapOut(flipOf(lp), amount);
        uint cakeBalance = IBEP20(CAKE).balanceOf(address(this));
        if (cakeBalance > 0) {
            _zapOut(CAKE, cakeBalance);
        }

        IPancakePair pair = IPancakePair(flipOf(lp));
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (token0 != WBNB) {
            _zapOut(token0, IBEP20(token0).balanceOf(address(this)));
        }
        if (token1 != WBNB) {
            _zapOut(token1, IBEP20(token1).balanceOf(address(this)));
        }
    }

    function _handleProfitAndLoss(address lp, address _account) private returns(uint profit, uint loss) {
        profit = 0;
        loss = 0;

        uint balance = address(this).balance;
        uint debt = bankBNB().accruedDebtValOf(lp, _account);
        if (balance >= debt) {
            _repay(lp, _account, debt);
            if (balance > debt) {
                profit = bankETH().transferProfit{ value: balance - debt }();
            }
        } else {
            _repay(lp, _account, balance);
            loss = bankETH().repayOrHandOverDebt(lp, _account, debt - balance);
        }
    }

    function _calculateTargetDebt(address pool, uint collateral, uint128 leverage) private view returns(uint targetDebtInBNB) {
        uint value = relayer.valueOfAsset(pool, collateral);
        uint bnbPrice = relayer.priceOf(WBNB);
        targetDebtInBNB = value.mul(leverage).div(bnbPrice);
    }

    function _calculateFlipAmountWithBNB(address flip, uint bnbAmount) private view returns(uint) {
        return relayer.valueOfAsset(WBNB, bnbAmount).mul(1e18).div(relayer.priceOf(flip));
    }

    function _borrow(address poolAddress, address _account, uint amount) private returns (uint debt) {
        (uint liquidity, uint utilized) = getUtilizationInfo();
        amount = Math.min(amount, liquidity.sub(utilized));
        if (amount == 0) return 0;

        return bankBNB().borrow(poolAddress, _account, amount);
    }

    function _repay(address poolAddress, address _account, uint amount) private returns (uint debt) {
        return bankBNB().repay{ value: amount }(poolAddress, _account);
    }

    function _zapOut(address token, uint amount) private {
        if (IBEP20(token).allowance(address(this), address(_zap)) == 0) {
            IBEP20(token).safeApprove(address(_zap), uint(-1));
        }
        _zap.zapOut(token, amount);
    }

    /* ========== DASHBOARD VIEW FUNCTIONS ========== */

    function withdrawAmount(address lp, address account, uint ratio) public override view returns(uint lpBalance, uint cakeBalance) {
        IStrategy cpool = IStrategy(cpoolOf(lp));
        lpBalance = cpool.balanceOf(account).mul(ratio).div(1e18);
        cakeBalance = cpool.earned(account);    // reward: CAKE
    }
}
