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
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./interfaces/legacy/IStrategyLegacy.sol";
import "./interfaces/IStrategy.sol";

contract MigratorV2 is Ownable {
    struct Status {
        address v1Address;
        address v2Address;

        IStrategyLegacy.UserInfo v1Info;    // v1 info

        bool needMigration; // true if v1's balance > 0 || wallets's balance > 0 || v2's balance > 0
        bool redeemed;      // true if (v1's balance == 0 && v1's profit == 0)
        bool approved;      // true if v2's allowance > 0
        bool deposited;     // true if v2's balance > 0
    }

    address[] private _vaults = [
    0x85537e99f5E535EdC72463e568CB3196130D1275, // CAKE
    0xed9BdC2E991fbEc75f0dD18b4110b8d49C79c5a9, // CAKE - BNB
    0x70368F425DCC37710a9982b4A4CE95fcBd009049, // BUSD - BNB
    0x655d5325C7510521c801E8F5ea074CDc1c9a3B71, // USDT - BNB
    0x8a5766863286789Ad185fd6505dA42a41137A044, // DAI - BNB
    0x828627292eD0A14C6b75Fa4ce9aa6fd859f20408, // USDC - BNB
    0x59E2a69c775991Ba1cb5540058428C28bE48da19, // USDT- BUSD
    0xeAbbadfF9857ef3200dE3518E1F964A9532cF9a5, // VAI - BUSD
    0xa3bFf2eFd9Bbeb098cc01A1285f7cA98227a52B1, // CakeMaximizer CAKE/BNB
    0x569b83F79Ab97757B6ab78ddBC40b1Eeb009d5AB, // CakeMaximizer BUSD/BNB
    0xDc6E9D719Be6Cc0EF4cD6484f7e215F904989bf8, // CakeMaximizer USDT/BNB
    0x916acb3e3b9f4B19FCfbFb327A64EA5e5FCbfbF0, // CakeMaximizer DAI/BNB
    0x62F2D4A792d13Da569Ec5fc0067dA71CaCB26609, // CakeMaximizer USDC/BNB
    0x3649b6d0Ab5727E0e02AC47AAfEC6b26e62fFa00, // CakeMaximizer USDT/BUSD
    0x23b68a3c008512a849981B6E69bBaC16048F3891 // CakeMaximizer VAI/BUSD
    ];

    address[] private _tokens = [
    0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82, // CAKE
    0xA527a61703D82139F8a06Bc30097cC9CAA2df5A6, // CAKE/BNB FLIP
    0x1B96B92314C44b159149f7E0303511fB2Fc4774f, // BUSD/BNB FLIP
    0x20bCC3b8a0091dDac2d0BC30F68E6CBb97de59Cd, // USDT/BNB FLIP
    0x56C77d59E82f33c712f919D09FcedDf49660a829, // DAI/BNB FLIP
    0x30479874f9320A62BcE3bc0e315C920E1D73E278, // USDC/BNB FLIP
    0xc15fa3E22c912A276550F3E5FE3b0Deb87B55aCd, // USDT/BUSD FLIP
    0xfF17ff314925Dff772b71AbdFF2782bC913B3575, // VAI/BUSD FLIP
    0xA527a61703D82139F8a06Bc30097cC9CAA2df5A6, // CakeMaximizer CAKE/BNB FLIP
    0x1B96B92314C44b159149f7E0303511fB2Fc4774f, // CakeMaximizer BUSD/BNB FLIP
    0x20bCC3b8a0091dDac2d0BC30F68E6CBb97de59Cd, // CakeMaximizer USDT/BNB FLIP
    0x56C77d59E82f33c712f919D09FcedDf49660a829, // CakeMaximizer DAI/BNB FLIP
    0x30479874f9320A62BcE3bc0e315C920E1D73E278, // CakeMaximizer USDC/BNB FLIP
    0xc15fa3E22c912A276550F3E5FE3b0Deb87B55aCd, // CakeMaximizer USDT/BUSD FLIP
    0xfF17ff314925Dff772b71AbdFF2782bC913B3575 // CakeMaximizer VAI/BUSD FLIP
    ];
    address[] private _v2 = [
    0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD, // CAKE
    0x7eaaEaF2aB59C2c85a17BEB15B110F81b192e98a, // CAKE - BNB
    0x1b6e3d394f1D809769407DEA84711cF57e507B99, // BUSD - BNB
    0xC1aAE51746bEA1a1Ec6f17A4f75b422F8a656ee6, // USDT - BNB
    0x93546BA555557049D94E58497EA8eb057a3df939, // DAI - BNB
    0x1D5C982bb7233d2740161e7bEddCC14548C71186, // USDC - BNB
    0xC0314BbE19D4D5b048D3A3B974f0cA1B2cEE5eF3, // USDT- BUSD
    0xa59EFEf41040e258191a4096DC202583765a43E7, // VAI - BUSD
    0x3f139386406b0924eF115BAFF71D0d30CC090Bd5, // CakeMaximizer CAKE/BNB
    0x92a0f75a0f07C90a7EcB65eDD549Fa6a45a4975C, // CakeMaximizer BUSD/BNB
    0xE07BdaAc4573a00208D148bD5b3e5d2Ae4Ebd0Cc, // CakeMaximizer USDT/BNB
    0x5d1dcB4460799F5d5A40a1F4ecA558ADE1c56831, // CakeMaximizer DAI/BNB
    0x87DFCd4032760936606C7A0ADBC7acec1885293F, // CakeMaximizer USDC/BNB
    0x866FD0028eb7fc7eeD02deF330B05aB503e199d4, // CakeMaximizer USDT/BUSD
    0xa5B8cdd3787832AdEdFe5a04bF4A307051538FF2 // CakeMaximizer VAI/BUSD
    ];

    // dev only
//    function setV2Address(address _address) external onlyOwner {
//        _v2.push(_address);
//    }

    function statusOf(address user) external view returns (bool showMigrationPage, Status[] memory outputs) {
        Status[] memory results = new Status[](_vaults.length);

        for (uint i = 0; i < _vaults.length; i++) {
            IBEP20 token = IBEP20(_tokens[i]);
            IStrategyLegacy v1 = IStrategyLegacy(_vaults[i]);
            IStrategy v2 = IStrategy(_v2[i]);

            Status memory status;
            status.v1Address = _vaults[i];
            status.v2Address = _v2[i];
            status.v1Info = v1.info(user);

            status.needMigration = v1.balanceOf(user) > 0 || token.balanceOf(user) > 0 || v2.balanceOf(user) > 0;
            status.redeemed = v1.balanceOf(user) == 0;
            status.approved = token.allowance(user, address(v2)) > 0;
            status.deposited = v2.balanceOf(user) > 0;

            if (v1.balanceOf(user) > 0 && showMigrationPage == false) {
                showMigrationPage = true;
            }
            results[i] = status;
        }

        outputs = results;
    }
}
