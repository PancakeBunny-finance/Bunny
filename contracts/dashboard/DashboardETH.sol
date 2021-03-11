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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/AggregatorV3Interface.sol";
import "../cvaults/eth/CVaultETHLP.sol";
import "../cvaults/CVaultRelayer.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract DashboardETH is OwnableUpgradeable {
    using SafeMath for uint;

    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory private constant factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    AggregatorV3Interface private constant ethPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    /* ========== STATE VARIABLES ========== */

    address payable public cvaultAddress;
    mapping(address => address) private pairAddresses;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== Restricted Operation ========== */

    function setCVaultAddress(address payable _cvaultAddress) external onlyOwner {
        cvaultAddress = _cvaultAddress;
    }

    function setPairAddress(address asset, address pair) external onlyOwner {
        pairAddresses[asset] = pair;
    }

    /* ========== Value Calculation ========== */

    function priceOfETH() view public returns (uint) {
        (, int price, , ,) = ethPriceFeed.latestRoundData();
        return uint(price).mul(1e10);
    }

    function pricesInUSD(address[] memory assets) public view returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            (, uint valueInUSD) = valueOfAsset(assets[i], 1e18);
            prices[i] = valueInUSD;
        }
        return prices;
    }

    function valueOfAsset(address asset, uint amount) public view returns (uint valueInETH, uint valueInUSD) {
        if (asset == address(0) || asset == address(WETH)) {
            valueInETH = amount;
            valueInUSD = amount.mul(priceOfETH()).div(1e18);
        } else if (keccak256(abi.encodePacked(IUniswapV2Pair(asset).symbol())) == keccak256("UNI-V2")) {
            if (IUniswapV2Pair(asset).token0() == address(WETH) || IUniswapV2Pair(asset).token1() == address(WETH)) {
                valueInETH = amount.mul(WETH.balanceOf(address(asset))).mul(2).div(IUniswapV2Pair(asset).totalSupply());
                valueInUSD = valueInETH.mul(priceOfETH()).div(1e18);
            } else {
                uint balanceToken0 = IERC20(IUniswapV2Pair(asset).token0()).balanceOf(asset);
                (uint token0PriceInETH,) = valueOfAsset(IUniswapV2Pair(asset).token0(), 1e18);

                valueInETH = amount.mul(balanceToken0).mul(2).mul(token0PriceInETH).div(1e18).div(IUniswapV2Pair(asset).totalSupply());
                valueInUSD = valueInETH.mul(priceOfETH()).div(1e18);
            }
        } else {
            address pairAddress = pairAddresses[asset];
            if (pairAddress == address(0)) {
                pairAddress = address(WETH);
            }

            uint decimalModifier = 0;
            uint decimals = uint(ERC20(asset).decimals());
            if (decimals < 18) {
                decimalModifier = 18 - decimals;
            }

            address pair = factory.getPair(asset, pairAddress);
            valueInETH = IERC20(pairAddress).balanceOf(pair).mul(amount).div(IERC20(asset).balanceOf(pair).mul(10 ** decimalModifier));
            if (pairAddress != address(WETH)) {
                (uint pairValueInETH,) = valueOfAsset(pairAddress, 1e18);
                valueInETH = valueInETH.mul(pairValueInETH).div(1e18);
            }
            valueInUSD = valueInETH.mul(priceOfETH()).div(1e18);
        }
    }

    /* ========== Collateral Calculation ========== */

    function collateralOfPool(address pool, address account) public view returns (uint collateralETH, uint collateralBSC, uint bnbDebt, uint leverage) {
        CVaultETHLPState.Account memory accountState = CVaultETHLP(cvaultAddress).accountOf(pool, account);
        collateralETH = accountState.collateral;
        collateralBSC = accountState.bscFlipBalance;
        bnbDebt = accountState.bscBNBDebt;
        leverage = accountState.leverage;
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint) {
        if (pool == address(0)) return 0;
        (, uint tvlInUSD) = valueOfAsset(pool, CVaultETHLP(cvaultAddress).totalCollateralOf(pool));
        return tvlInUSD;
    }

    /* ========== Pool Information ========== */

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfoETH memory) {
        PoolConstant.PoolInfoETH memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        CVaultETHLP cvault = CVaultETHLP(cvaultAddress);
        CVaultETHLPState.Account memory accountState = cvault.accountOf(pool, account);

        (uint collateralETH, uint collateralBSC, uint bnbDebt, uint leverage) = collateralOfPool(pool, account);
        poolInfo.pool = pool;
        poolInfo.collateralETH = collateralETH;
        poolInfo.collateralBSC = collateralBSC;
        poolInfo.bnbDebt = bnbDebt;
        poolInfo.leverage = leverage;
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.updatedAt = accountState.updatedAt;
        poolInfo.depositedAt = accountState.depositedAt;
        poolInfo.feeDuration = cvault.WITHDRAWAL_FEE_PERIOD();
        poolInfo.feePercentage = cvault.WITHDRAWAL_FEE();
        return poolInfo;
    }
}
