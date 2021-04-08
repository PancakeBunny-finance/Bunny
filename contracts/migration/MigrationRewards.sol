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

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MigrationRewards is Ownable, ReentrancyGuard {
    using SafeBEP20 for IBEP20;

    struct Request {
        address account;
        uint rewards;
    }

    event MigrationRewardsPaid(address indexed account, uint amount);
    event EmergencyExit(address indexed token, uint amount);

    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    mapping(address => uint) public rewards;

    function getReward() public nonReentrant {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;

            BUNNY.safeTransfer(msg.sender, reward);
            emit MigrationRewardsPaid(msg.sender, reward);
        }
    }

    function updateRewards(Request[] memory requests) external onlyOwner {
        for (uint i = 0; i < requests.length; i++) {
            Request memory request = requests[i];
            rewards[request.account] = request.rewards;
        }
    }

    function emergencyExit(address token) external onlyOwner {
        IBEP20 asset = IBEP20(token);

        uint remain = asset.balanceOf(address(this));
        asset.safeTransfer(owner(), remain);
        emit EmergencyExit(token, remain);
    }
}
