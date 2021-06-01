// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

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

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../interfaces/IBank.sol";


contract BankConfig is IBankConfig, Ownable {
    /// The portion of interests allocated to the reserve pool.
    uint public override getReservePoolBps;

    /// Interest rate model
    InterestModel public interestModel;

    constructor(uint _reservePoolBps, InterestModel _interestModel) public {
        setParams(_reservePoolBps, _interestModel);
    }

    /// @dev Set all the basic parameters. Must only be called by the owner.
    /// @param _reservePoolBps The new interests allocated to the reserve pool value.
    /// @param _interestModel The new interest rate model contract.
    function setParams(uint _reservePoolBps, InterestModel _interestModel) public onlyOwner {
        getReservePoolBps = _reservePoolBps;
        interestModel = _interestModel;
    }

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint debt, uint floating) external view override returns (uint) {
        return interestModel.getInterestRate(debt, floating);
    }
}
