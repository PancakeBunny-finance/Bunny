// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../library/legacy/Pausable.sol";
import "../../../library/SafeToken.sol";

import "../../../interfaces/IPancakeRouter02.sol";
import "../../../interfaces/IVenusDistribution.sol";
import "../../../interfaces/IVBNB.sol";


contract StrategyVBNB is ReentrancyGuard, Pausable {
    using SafeToken for address;
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address private constant vBNB = 0xA07c5b74C9B40447a954e1466938b865b6BBea36;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant XVS = 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63;
    address private constant VENUS_UNITROLLER = 0xfD36E2c2a6789Db23113685031d7F16329158384;
    address private constant PANCAKESWAP_ROUTER = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;

    address private constant KEEPER = 0x793074D9799DC3c6039F8056F1Ba884a73462051;

    address public bankBNB;
    uint256 public sharesTotal;

    /**
     * @dev Variables that can be changed to config profitability and risk:
     * {borrowRate}          - What % of our collateral do we borrow per leverage level.
     * {borrowDepth}         - How many levels of leverage do we take.
     * {BORROW_RATE_MAX}     - A limit on how much we can push borrow risk.
     * {BORROW_DEPTH_MAX}    - A limit on how many steps we can leverage.
     */
    uint256 public borrowRate;
    uint256 public borrowDepth;
    uint256 public constant BORROW_RATE_MAX = 595;
    uint256 public constant BORROW_RATE_MAX_HARD = 599;
    uint256 public constant BORROW_DEPTH_MAX = 6;

    uint256 public supplyBal; // Cached want supplied to venus
    uint256 public borrowBal; // Cached want borrowed from venus
    uint256 public supplyBalTargeted; // Cached targeted want supplied to venus to achieve desired leverage
    uint256 public supplyBalMin;

    modifier onlyBank {
        require(msg.sender == bankBNB, "StrategyVBNB: not bank");
        _;
    }

    modifier onlyKeeper {
        require(msg.sender == KEEPER || msg.sender == owner(), "StrategyVBNB: not keeper");
        _;
    }

    receive() payable external {}

    constructor(address _bankBNB) public {
        bankBNB = _bankBNB;

        IERC20(XVS).safeApprove(PANCAKESWAP_ROUTER, uint256(-1));

        address[] memory venusMarkets = new address[](1);
        venusMarkets[0] = vBNB;
        IVenusDistribution(VENUS_UNITROLLER).enterMarkets(venusMarkets);

        borrowRate = 585;
        borrowDepth = 3;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function wantLockedTotal() public view returns (uint256) {
        return wantLockedInHere().add(supplyBal).sub(borrowBal);
    }

    function wantLockedInHere() public view returns (uint256) {
        return address(this).balance;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @dev Updates the risk profile and rebalances the vault funds accordingly.
    /// @param _borrowRate percent to borrow on each leverage level.
    /// @param _borrowDepth how many levels to leverage the funds.
    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external onlyOwner {
        require(_borrowRate <= BORROW_RATE_MAX, "!rate");
        require(_borrowDepth <= BORROW_DEPTH_MAX, "!depth");

        _deleverage(false, uint256(-1)); // deleverage all supplied want tokens
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;
        _farm(true);
    }

    function harvest() external notPaused onlyKeeper {
        _harvest();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() external onlyOwner {
        paused = true;
        lastPauseTime = block.timestamp;

        IERC20(XVS).safeApprove(PANCAKESWAP_ROUTER, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        paused = false;

        IERC20(XVS).safeApprove(PANCAKESWAP_ROUTER, uint256(-1));
    }

    function recoverToken(address _token, uint256 _amount, address _to) public onlyOwner {
        require(_token != XVS, "!safe");
        require(_token != vBNB, "!safe");

        IERC20(_token).safeTransfer(_to, _amount);
    }

    // ---------- VAULT FUNCTIONS ----------

    function deposit() public payable nonReentrant notPaused {
        _farm(true);
    }

    function withdraw(address account, uint256 _wantAmt) external onlyBank nonReentrant {
        uint256 wantBal = address(this).balance;
        if (wantBal < _wantAmt) {
            _deleverage(true, _wantAmt.sub(wantBal));
            wantBal = address(this).balance;
        }

        if (wantBal < _wantAmt) {
            _wantAmt = wantBal;
        }

        SafeToken.safeTransferETH(account, _wantAmt);

        if(address(this).balance > 1 szabo) {
            _farm(true);
        }
    }

    function migrate(address payable to) external onlyBank {
        _harvest();
        _deleverage(false, uint(-1));
        StrategyVBNB(to).deposit{ value: address(this).balance }();
    }

    // ---------- PUBLIC ----------
    /**
    * @dev Redeem to the desired leverage amount, then use it to repay borrow.
    * If already over leverage, redeem max amt redeemable, then use it to repay borrow.
    */
    function deleverageOnce() public {
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

        if (supplyBal <= supplyBalTargeted) {
            _removeSupply(supplyBal.sub(supplyBalMin));
        } else {
            _removeSupply(supplyBal.sub(supplyBalTargeted));
        }

        _repayBorrow(address(this).balance);

        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin
    }

    /**
     * @dev Redeem the max possible, use it to repay borrow
     */
    function deleverageUntilNotOverLevered() public {
        // updateBalance(); // To be more accurate, call updateBalance() first to cater for changes due to interest rates

        // If borrowRate slips below targeted borrowRate, withdraw the max amt first.
        // Further actual deleveraging will take place later on.
        // (This can happen in when net interest rate < 0, and supplied balance falls below targeted.)
        while (supplyBal > 0 && supplyBal <= supplyBalTargeted) {
            deleverageOnce();
        }
    }

    function farm(bool _withLev) public nonReentrant {
        _farm(_withLev);
    }

    /**
    * @dev Updates want locked in Venus after interest is accrued to this very block.
    * To be called before sensitive operations.
    */
    function updateBalance() public {
        supplyBal = IVBNB(vBNB).balanceOfUnderlying(address(this)); // a payable function because of accrueInterest()
        borrowBal = IVBNB(vBNB).borrowBalanceCurrent(address(this));
        supplyBalTargeted = borrowBal.mul(1000).div(borrowRate);
        supplyBalMin = borrowBal.mul(1000).div(BORROW_RATE_MAX_HARD);
    }

    // ---------- PRIVATE ----------
    function _farm(bool _withLev) private {
        uint balance = address(this).balance;
        if (balance > 1 szabo) {
            _leverage(address(this).balance, _withLev);
            updateBalance();
        }

        deleverageUntilNotOverLevered(); // It is possible to still be over-levered after depositing.
    }

    function _harvest() private {
        IVenusDistribution(VENUS_UNITROLLER).claimVenus(address(this));

        uint256 earnedAmt = IERC20(XVS).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = XVS;
        path[1] = WBNB;
        IPancakeRouter02(PANCAKESWAP_ROUTER).swapExactTokensForETH(
            earnedAmt,
            0,
            path,
            address(this),
            block.timestamp
        );

        _farm(false); // Supply wantToken without leverage, to cater for net -ve interest rates.
    }

    /**
     * @dev Repeatedly supplies and borrows bnb following the configured {borrowRate} and {borrowDepth}
     * into the vToken contract.
     */
    function _leverage(uint256 _amount, bool _withLev) private {
        if (_withLev) {
            for (uint256 i = 0; i < borrowDepth; i++) {
                _supply(_amount);
                _amount = _amount.mul(borrowRate).div(1000);
                _borrow(_amount);
            }
        }

        _supply(_amount); // Supply remaining want that was last borrowed.
    }

    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this untill all want tokens is withdrawn. For partial deleveraging,
     * this continues until at least _minAmt of want tokens is reached.
     */

    function _deleverage(bool _delevPartial, uint256 _minAmt) private {
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

        deleverageUntilNotOverLevered();

        _removeSupply(supplyBal.sub(supplyBalMin));

        uint256 wantBal = wantLockedInHere();

        // Recursively repay borrowed + remove more from supplied
        while (wantBal < borrowBal) {
            // If only partially deleveraging, when sufficiently deleveraged, do not repay anymore
            if (_delevPartial && wantBal >= _minAmt) {
                return;
            }

            _repayBorrow(wantBal);

            updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

            _removeSupply(supplyBal.sub(supplyBalMin));

            wantBal = wantLockedInHere();
        }

        // If only partially deleveraging, when sufficiently deleveraged, do not repay
        if (_delevPartial && wantBal >= _minAmt) {
            return;
        }

        // Make a final repayment of borrowed
        _repayBorrow(borrowBal);

        // remove all supplied
        uint256 vTokenBal = IERC20(vBNB).balanceOf(address(this));
        IVBNB(vBNB).redeem(vTokenBal);
    }

    function _supply(uint256 _amount) private {
        IVBNB(vBNB).mint{ value: _amount }();
    }

    function _removeSupply(uint256 amount) private {
        IVBNB(vBNB).redeemUnderlying(amount);
    }

    function _borrow(uint256 _amount) private {
        IVBNB(vBNB).borrow(_amount);
    }

    function _repayBorrow(uint256 _amount) private {
        IVBNB(vBNB).repayBorrow{value: _amount}();
    }
}
