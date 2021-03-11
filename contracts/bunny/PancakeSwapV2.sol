// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";

abstract contract PancakeSwapV2 is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    IPancakeFactory private constant FACTORY = IPancakeFactory(0xBCfCcbde45cE874adCB698cC183deBcF17952812);

    address internal constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address internal constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function __PancakeSwapV2_init() internal initializer {
        __Ownable_init();
    }

    function tokenToBunnyBNB(address token, uint amount) internal returns(uint flipAmount) {
        if (token == CAKE) {
            flipAmount = _cakeToBunnyBNBFlip(amount);
        } else if (token == BUNNY) {
            // Burn BUNNY!!
            IBEP20(BUNNY).transfer(DEAD, amount);
            flipAmount = 0;
        } else {
            // flip
            flipAmount = _flipToBunnyBNBFlip(token, amount);
        }
    }

    function _cakeToBunnyBNBFlip(uint amount) private returns(uint flipAmount) {
        swapToken(CAKE, amount.div(2), BUNNY);
        swapToken(CAKE, amount.sub(amount.div(2)), WBNB);

        flipAmount = generateFlipToken();
    }

    function _flipToBunnyBNBFlip(address flip, uint amount) private returns(uint flipAmount) {
        IPancakePair pair = IPancakePair(flip);
        address _token0 = pair.token0();
        address _token1 = pair.token1();
        _approveTokenIfNeeded(flip);
        ROUTER.removeLiquidity(_token0, _token1, amount, 0, 0, address(this), block.timestamp);
        if (_token0 == WBNB) {
            swapToken(_token1, IBEP20(_token1).balanceOf(address(this)), BUNNY);
            flipAmount = generateFlipToken();
        } else if (_token1 == WBNB) {
            swapToken(_token0, IBEP20(_token0).balanceOf(address(this)), BUNNY);
            flipAmount = generateFlipToken();
        } else {
            swapToken(_token0, IBEP20(_token0).balanceOf(address(this)), BUNNY);
            swapToken(_token1, IBEP20(_token1).balanceOf(address(this)), WBNB);
            flipAmount = generateFlipToken();
        }
    }

    function swapToken(address _from, uint _amount, address _to) private {
        if (_from == _to) return;

        address[] memory path;
        if (_from == WBNB || _to == WBNB) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = WBNB;
            path[2] = _to;
        }
        _approveTokenIfNeeded(_from);
        ROUTER.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp);
    }

    function generateFlipToken() private returns(uint liquidity) {
        uint amountADesired = IBEP20(BUNNY).balanceOf(address(this));
        uint amountBDesired = IBEP20(WBNB).balanceOf(address(this));
        _approveTokenIfNeeded(BUNNY);
        _approveTokenIfNeeded(WBNB);

        (,,liquidity) = ROUTER.addLiquidity(BUNNY, WBNB, amountADesired, amountBDesired, 0, 0, address(this), block.timestamp);

        // send dust
        IBEP20(BUNNY).transfer(msg.sender, IBEP20(BUNNY).balanceOf(address(this)));
        IBEP20(WBNB).transfer(msg.sender, IBEP20(WBNB).balanceOf(address(this)));
    }

    function _approveTokenIfNeeded(address token) private {
        if (IBEP20(token).allowance(address(this), address(ROUTER)) == 0) {
            IBEP20(token).safeApprove(address(ROUTER), uint(-1));
        }
    }
}