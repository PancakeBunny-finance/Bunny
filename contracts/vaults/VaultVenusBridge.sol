// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../library/SafeToken.sol";
import "../library/Whitelist.sol";

import "../interfaces/IVaultVenusBridge.sol";
import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IVenusDistribution.sol";
import "../interfaces/IVBNB.sol";
import "../interfaces/IVToken.sol";
import "./venus/Exponential.sol";


contract VaultVenusBridge is Whitelist, Exponential, IVaultVenusBridge {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    IPancakeRouter02 private constant PANCAKE_ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    IVenusDistribution private constant VENUS_UNITROLLER = IVenusDistribution(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    IBEP20 private constant XVS = IBEP20(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    IVBNB public constant vBNB = IVBNB(0xA07c5b74C9B40447a954e1466938b865b6BBea36);

    /* ========== STATE VARIABLES ========== */

    MarketInfo[] private _marketList;
    mapping(address => MarketInfo) markets;

    /* ========== EVENTS ========== */

    event Recovered(address token, uint amount);

    /* ========== MODIFIERS ========== */

    modifier updateAvailable(address vault) {
        MarketInfo storage market = markets[vault];
        uint tokenBalanceBefore = market.token != WBNB ? IBEP20(market.token).balanceOf(address(this)) : address(this).balance;
        uint vTokenAmountBefore = IBEP20(market.vToken).balanceOf(address(this));

        _;

        uint tokenBalance = market.token != WBNB ? IBEP20(market.token).balanceOf(address(this)) : address(this).balance;
        uint vTokenAmount = IBEP20(market.vToken).balanceOf(address(this));
        market.available = market.available.add(tokenBalance).sub(tokenBalanceBefore);
        market.vTokenAmount = market.vTokenAmount.add(vTokenAmount).sub(vTokenAmountBefore);
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    constructor() public {
        XVS.safeApprove(address(PANCAKE_ROUTER), uint(- 1));
    }

    /* ========== VIEW FUNCTIONS ========== */

    function infoOf(address vault) public view override returns (MarketInfo memory) {
        return markets[vault];
    }

    function availableOf(address vault) public view override returns (uint) {
        return markets[vault].available;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addVault(address vault, address token, address vToken) public onlyOwner {
        require(markets[vault].token == address(0), "VaultVenusBridge: vault is already set");
        require(token != address(0) && vToken != address(0), "VaultVenusBridge: invalid tokens");

        MarketInfo memory market = MarketInfo(token, vToken, 0, 0);
        _marketList.push(market);
        markets[vault] = market;

        IBEP20(token).safeApprove(address(PANCAKE_ROUTER), uint(- 1));
        IBEP20(token).safeApprove(vToken, uint(- 1));

        address[] memory venusMarkets = new address[](1);
        venusMarkets[0] = vToken;
        VENUS_UNITROLLER.enterMarkets(venusMarkets);
    }

    function migrateTo(address payable target) external override onlyWhitelisted {
        MarketInfo storage market = markets[msg.sender];
        IVaultVenusBridge newBridge = IVaultVenusBridge(target);

        if (market.token == WBNB) {
            newBridge.deposit{value : market.available}(msg.sender, market.available);
        } else {
            IBEP20 token = IBEP20(market.token);
            token.safeApprove(address(newBridge), uint(- 1));
            token.safeTransfer(address(newBridge), market.available);
            token.safeApprove(address(newBridge), 0);
            newBridge.deposit(msg.sender, market.available);
        }
        market.available = 0;
        market.vTokenAmount = 0;
    }

    function deposit(address vault, uint amount) external override payable onlyWhitelisted {
        MarketInfo storage market = markets[vault];
        market.available = market.available.add(msg.value > 0 ? msg.value : amount);
    }

    function withdraw(address account, uint amount) external override onlyWhitelisted {
        MarketInfo storage market = markets[msg.sender];
        market.available = market.available.sub(amount);
        if (market.token == WBNB) {
            SafeToken.safeTransferETH(account, amount);
        } else {
            IBEP20(market.token).safeTransfer(account, amount);
        }
    }

    function harvest() public override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];

        address[] memory vTokens = new address[](1);
        vTokens[0] = market.vToken;

        uint before = XVS.balanceOf(address(this));
        VENUS_UNITROLLER.claimVenus(address(this), vTokens);

        uint xvsBalance = XVS.balanceOf(address(this)).sub(before);
        if (xvsBalance > 0) {
            if (market.token == WBNB) {
                address[] memory path = new address[](2);
                path[0] = address(XVS);
                path[1] = WBNB;
                PANCAKE_ROUTER.swapExactTokensForETH(xvsBalance, 0, path, address(this), block.timestamp);
            } else {
                address[] memory path = new address[](3);
                path[0] = address(XVS);
                path[1] = WBNB;
                path[2] = market.token;
                PANCAKE_ROUTER.swapExactTokensForTokens(xvsBalance, 0, path, address(this), block.timestamp);
            }
        }
    }

    function balanceOfUnderlying(address vault) external override returns (uint) {
        MarketInfo memory market = markets[vault];
        Exp memory exchangeRate = Exp({mantissa: IVToken(market.vToken).exchangeRateCurrent()});
        (MathError mErr, uint balance) = mulScalarTruncate(exchangeRate, market.vTokenAmount);
        require(mErr == MathError.NO_ERROR, "balance could not be calculated");
        return balance;
    }

    /* ========== VENUS FUNCTIONS ========== */

    function mint(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        if (market.token == WBNB) {
            vBNB.mint{value : amount}();
        } else {
            IVToken(market.vToken).mint(amount);
        }
    }

    function redeemUnderlying(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        IVToken vToken = IVToken(market.vToken);
        vToken.redeemUnderlying(amount);
    }

    function redeemAll() external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        IVToken vToken = IVToken(market.vToken);
        vToken.redeem(market.vTokenAmount);
    }

    function borrow(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        IVToken vToken = IVToken(market.vToken);
        vToken.borrow(amount);
    }

    function repayBorrow(uint amount) external override updateAvailable(msg.sender) onlyWhitelisted {
        MarketInfo memory market = markets[msg.sender];
        if (market.vToken == address(vBNB)) {
            vBNB.repayBorrow{value : amount}();
        } else {
            IVToken(market.vToken).repayBorrow(amount);
        }
    }

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

            if (market.vToken == token) {
                revert("VaultVenusBridge: cannot recover");
            }

            if (market.token == token) {
                uint balance = token == WBNB ? address(this).balance : IBEP20(token).balanceOf(address(this));
                require(balance.sub(market.available) >= amount, "VaultVenusBridge: cannot recover");

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
