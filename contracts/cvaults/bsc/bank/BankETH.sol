// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../../../interfaces/IPancakePair.sol";
import "../../../interfaces/IPancakeRouter02.sol";

import "../../../library/PausableUpgradeable.sol";
import "../../../library/Whitelist.sol";
import "../../interface/IBankBNB.sol";
import "../../interface/IBankETH.sol";


contract BankETH is IBankETH, PausableUpgradeable, Whitelist {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint private constant PERFORMANCE_FEE_MAX = 10000;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

    /* ========== STATE VARIABLES ========== */

    uint public PERFORMANCE_FEE;
    uint private _treasuryFund;
    uint private _treasuryDebt;
    address public keeper;
    address public bankBNB;

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), "BankETH: not keeper");
        _;
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __PausableUpgradeable_init();
        __Whitelist_init();

        PERFORMANCE_FEE = 1000;
        IBEP20(ETH).safeApprove(address(ROUTER), uint(-1));
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balance() external view returns(uint) {
        return IBEP20(ETH).balanceOf(address(this));
    }

    function treasuryFund() external view returns(uint) {
        return _treasuryFund;
    }

    function treasuryDebt() external view returns(uint) {
        return _treasuryDebt;
    }

    /* ========== RESTRICTED FUNCTIONS - OWNER ========== */

    function setKeeper(address newKeeper) external onlyOwner {
        keeper = newKeeper;
    }

    function setPerformanceFee(uint newPerformanceFee) external onlyOwner {
        require(newPerformanceFee <= 5000, "BankETH: fee too much");
        PERFORMANCE_FEE = newPerformanceFee;
    }

    function recoverToken(address _token, uint amount) external onlyOwner {
        require(_token != ETH, 'BankETH: cannot recover eth token');
        if (_token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IBEP20(_token).safeTransfer(owner(), amount);
        }
    }

    function setBankBNB(address newBankBNB) external onlyOwner {
        require(bankBNB == address(0), "BankETH: bankBNB is already set");
        bankBNB = newBankBNB;

        IBEP20(ETH).safeApprove(newBankBNB, uint(-1));
    }

    /* ========== RESTRICTED FUNCTIONS - KEEPER ========== */

    function repayTreasuryDebt() external onlyKeeper returns(uint ethAmount) {
        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        uint debt = IBankBNB(bankBNB).accruedDebtValOf(address(this), address(this));
        ethAmount = ROUTER.getAmountsIn(debt, path)[0];
        require(ethAmount <= IBEP20(ETH).balanceOf(address(this)), "BankETH: insufficient eth");

        if (_treasuryDebt >= ethAmount) {
            _treasuryFund = _treasuryFund.add(_treasuryDebt.sub(ethAmount));
            _treasuryDebt = 0;
            _repayTreasuryDebt(debt, ethAmount);
        } else if (_treasuryDebt.add(_treasuryFund) >= ethAmount) {
            _treasuryFund = _treasuryFund.sub(ethAmount.sub(_treasuryDebt));
            _treasuryDebt = 0;
            _repayTreasuryDebt(debt, ethAmount);
        } else {
            revert("BankETH: not enough eth balance");
        }
    }

    // panama bridge
    function transferTreasuryFund(address to, uint ethAmount) external onlyKeeper {
        IBEP20(ETH).safeTransfer(to, ethAmount);
    }

    /* ========== RESTRICTED FUNCTIONS - WHITELISTED ========== */

    function repayOrHandOverDebt(address lp, address account, uint debt) external override onlyWhitelisted returns(uint ethAmount)  {
        if (debt == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        ethAmount = ROUTER.getAmountsIn(debt, path)[0];
        uint ethBalance = IBEP20(ETH).balanceOf(address(this));
        if (ethAmount <= ethBalance) {
            // repay
            uint[] memory amounts = ROUTER.swapTokensForExactETH(debt, ethAmount, path, address(this), block.timestamp);
            IBankBNB(bankBNB).repay{ value: amounts[1] }(lp, account);
        } else {
            if (ethBalance > 0) {
                uint[] memory amounts = ROUTER.swapExactTokensForETH(ethBalance, 0, path, address(this), block.timestamp);
                IBankBNB(bankBNB).repay{ value: amounts[1] }(lp, account);
            }

            _treasuryDebt = _treasuryDebt.add(ethAmount.sub(ethBalance));
            // insufficient ETH !!!!
            // handover BNB debt
            IBankBNB(bankBNB).handOverDebtToTreasury(lp, account);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function depositTreasuryFund(uint ethAmount) external {
        IBEP20(ETH).transferFrom(msg.sender, address(this), ethAmount);
        _treasuryFund = _treasuryFund.add(ethAmount);
    }

    function transferProfit() external override payable returns(uint ethAmount) {
        if (msg.value == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = ETH;

        uint[] memory amounts = ROUTER.swapExactETHForTokens{ value : msg.value }(0, path, address(this), block.timestamp);
        uint fee = amounts[1].mul(PERFORMANCE_FEE).div(PERFORMANCE_FEE_MAX);

        _treasuryFund = _treasuryFund.add(fee);
        ethAmount = amounts[1].sub(fee);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _repayTreasuryDebt(uint debt, uint maxETHAmount) private {
        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        uint[] memory amounts = ROUTER.swapTokensForExactETH(debt, maxETHAmount, path, address(this), block.timestamp);
        IBankBNB(bankBNB).repayTreasuryDebt{ value: amounts[1] }();
    }
}
