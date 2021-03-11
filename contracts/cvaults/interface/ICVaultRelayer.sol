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


interface ICVaultRelayer {

    struct RelayRequest {
        address lp;
        address account;
        uint8 signature;
        uint8 validation;
        uint112 nonce;
        uint128 requestId;
        uint128 leverage;
        uint collateral;
        uint lpValue;
    }

    struct RelayResponse {
        address lp;
        address account;
        uint8 signature;
        uint8 validation;
        uint112 nonce;
        uint128 requestId;
        uint bscBNBDebtShare;
        uint bscFlipBalance;
        uint ethProfit;
        uint ethLoss;
    }

    struct RelayLiquidation {
        address lp;
        address account;
        address liquidator;
    }

    struct RelayUtilization {
        uint liquidity;
        uint utilized;
    }

    struct RelayHistory {
        uint128 requestId;
        RelayRequest request;
        RelayResponse response;
    }

    struct RelayOracleData {
        address token;
        uint price;
    }

    function requestRelayOnETH(address lp, address account, uint8 signature, uint128 leverage, uint collateral, uint lpAmount) external returns(uint requestId);

    function askLiquidationFromHandler(RelayLiquidation[] memory _candidate) external;
    function askLiquidationFromCVaultETH(address lp, address account, address liquidator) external;
    function executeLiquidationOnETH() external;

    function valueOfAsset(address token, uint amount) external view returns(uint);
    function priceOf(address token) external view returns(uint);
    function collateralRatioOnETH(address lp, uint lpAmount, address flip, uint flipAmount, uint debt) external view returns(uint);
    function utilizationInfo() external view returns (uint total, uint utilized);
    function isUtilizable(address lp, uint amount, uint leverage) external view returns(bool);
}
