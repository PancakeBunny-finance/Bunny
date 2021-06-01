// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../library/SafeToken.sol";
import "../library/PausableUpgradeable.sol";
import "../library/WhitelistUpgradeable.sol";
import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IBank.sol";


contract BankBridge is IBankBridge, PausableUpgradeable, WhitelistUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    uint private constant RESERVE_RATIO_UNIT = 10000;
    uint private constant RESERVE_RATIO_LIMIT = 5000;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    /* ========== STATE VARIABLES ========== */

    address public bank;

    uint public reserveRatio;
    uint public reserved;

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        reserveRatio = 1000;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balance() public view returns (uint) {
        return IBEP20(ETH).balanceOf(address(this));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setReserveRatio(uint newReserveRatio) external onlyOwner {
        require(newReserveRatio <= RESERVE_RATIO_LIMIT, "BankBridge: invalid reserve ratio");
        reserveRatio = newReserveRatio;
    }

    function setBank(address payable newBank) external onlyOwner {
        require(address(bank) == address(0), "BankBridge: bank exists");
        bank = newBank;
    }

    function approveETH() external onlyOwner {
        IBEP20(ETH).approve(address(ROUTER), uint(-1));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function realizeProfit() external override payable onlyWhitelisted returns (uint profitInETH) {
        if (msg.value == 0) return 0;

        uint reserve = msg.value.mul(reserveRatio).div(RESERVE_RATIO_UNIT);
        reserved = reserved.add(reserve);

        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = ETH;

        return ROUTER.swapExactETHForTokens{value : msg.value.sub(reserve)}(0, path, address(this), block.timestamp)[1];
    }

    function realizeLoss(uint loss) external override onlyWhitelisted returns (uint lossInETH) {
        if (loss == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        lossInETH = ROUTER.getAmountsIn(loss, path)[0];
        uint ethBalance = IBEP20(ETH).balanceOf(address(this));
        if (ethBalance >= lossInETH) {
            uint bnbOut = ROUTER.swapTokensForExactETH(loss, lossInETH, path, address(this), block.timestamp)[1];
            SafeToken.safeTransferETH(bank, bnbOut);
            return 0;
        } else {
            if (ethBalance > 0) {
                uint bnbOut = ROUTER.swapExactTokensForETH(ethBalance, 0, path, address(this), block.timestamp)[1];
                SafeToken.safeTransferETH(bank, bnbOut);
            }
            lossInETH = lossInETH.sub(ethBalance);
        }
    }

    function bridgeETH(address to, uint amount) external onlyWhitelisted {
        if (IBEP20(ETH).allowance(address(this), address(to)) == 0) {
            IBEP20(ETH).safeApprove(address(to), uint(- 1));
        }
        IBEP20(ETH).safeTransfer(to, amount);
    }
}
