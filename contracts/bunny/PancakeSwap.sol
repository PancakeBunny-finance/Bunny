// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";

abstract contract PancakeSwap {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    IPancakeFactory private constant factory = IPancakeFactory(0xBCfCcbde45cE874adCB698cC183deBcF17952812);

    address internal constant cake = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address private constant _bunny = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address private constant _wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function bunnyBNBFlipToken() internal view returns(address) {
        return factory.getPair(_bunny, _wbnb);
    }

    function tokenToBunnyBNB(address token, uint amount) internal returns(uint flipAmount) {
        if (token == cake) {
            flipAmount = _cakeToBunnyBNBFlip(amount);
        } else {
            // flip
            flipAmount = _flipToBunnyBNBFlip(token, amount);
        }
    }

    function _cakeToBunnyBNBFlip(uint amount) private returns(uint flipAmount) {
        swapToken(cake, amount.div(2), _bunny);
        swapToken(cake, amount.sub(amount.div(2)), _wbnb);

        flipAmount = generateFlipToken();
    }

    function _flipToBunnyBNBFlip(address token, uint amount) private returns(uint flipAmount) {
        IPancakePair pair = IPancakePair(token);
        address _token0 = pair.token0();
        address _token1 = pair.token1();
        IBEP20(token).safeApprove(address(ROUTER), 0);
        IBEP20(token).safeApprove(address(ROUTER), amount);
        ROUTER.removeLiquidity(_token0, _token1, amount, 0, 0, address(this), block.timestamp);
        if (_token0 == _wbnb) {
            swapToken(_token1, IBEP20(_token1).balanceOf(address(this)), _bunny);
            flipAmount = generateFlipToken();
        } else if (_token1 == _wbnb) {
            swapToken(_token0, IBEP20(_token0).balanceOf(address(this)), _bunny);
            flipAmount = generateFlipToken();
        } else {
            swapToken(_token0, IBEP20(_token0).balanceOf(address(this)), _bunny);
            swapToken(_token1, IBEP20(_token1).balanceOf(address(this)), _wbnb);
            flipAmount = generateFlipToken();
        }
    }

    function swapToken(address _from, uint _amount, address _to) private {
        if (_from == _to) return;

        address[] memory path;
        if (_from == _wbnb || _to == _wbnb) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = _wbnb;
            path[2] = _to;
        }

        IBEP20(_from).safeApprove(address(ROUTER), 0);
        IBEP20(_from).safeApprove(address(ROUTER), _amount);
        ROUTER.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp);
    }

    function generateFlipToken() private returns(uint liquidity) {
        uint amountADesired = IBEP20(_bunny).balanceOf(address(this));
        uint amountBDesired = IBEP20(_wbnb).balanceOf(address(this));

        IBEP20(_bunny).safeApprove(address(ROUTER), 0);
        IBEP20(_bunny).safeApprove(address(ROUTER), amountADesired);
        IBEP20(_wbnb).safeApprove(address(ROUTER), 0);
        IBEP20(_wbnb).safeApprove(address(ROUTER), amountBDesired);

        (,,liquidity) = ROUTER.addLiquidity(_bunny, _wbnb, amountADesired, amountBDesired, 0, 0, address(this), block.timestamp);

        // send dust
        IBEP20(_bunny).transfer(msg.sender, IBEP20(_bunny).balanceOf(address(this)));
        IBEP20(_wbnb).transfer(msg.sender, IBEP20(_wbnb).balanceOf(address(this)));
    }
}