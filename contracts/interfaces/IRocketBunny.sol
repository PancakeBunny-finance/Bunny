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

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;


interface IRocketBunny {

    // Swap for simple auction and Callback for delegate contract
    enum AuctionOpts {
        Swap, Callback
    }

    struct AuctionInfo {
        string name;                    // auction name
        uint deadline;                  // auction deadline
        uint swapRatio;                 // swap ratio [1-100000000]
        uint allocation;                // allocation per wallet
        uint tokenSupply;               // amount of the pre-sale token
        uint tokenRemain;               // remain of the pre-sale token
        uint capacity;                  // total value of pre-sale token in ETH or BNB (calculated by RocketBunny)
        uint engaged;                   // total raised fund value ()
        address token;                  // address of the pre-sale token
        address payable beneficiary;    // auction host (use contract address for AuctionOpts.Callback)
        bool archived;                  // flag to determine archived
        AuctionOpts option;             // options [Swap, Callback]
    }

    struct UserInfo {
        uint engaged;
        bool claim;
    }

    function getAuction(uint id) external view returns (AuctionInfo memory);

    /**
     * @dev User's amount and boolean flag for claim
     * @param id Auction ID
     * @param user User's address
     * @return True for already claimed
     */
    function getUserInfo(uint id, address user) external view returns (UserInfo memory);

    /**
     * @dev Calculate the amount of tokens for the funds raised.
     * @param id Auction ID
     * @param amount Raised amount (ETH/BNB)
     * @return The amount of tokens swapped
     */
    function swapTokenAmount(uint id, uint amount) external view returns (uint);

    function archive(uint id) external;
}
