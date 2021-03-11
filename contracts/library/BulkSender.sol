// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract BulkSender {
    struct Receiver {
        address to;
        uint amount;
    }

    function send(address token, Receiver[] memory receivers) external {
        uint sum;
        for(uint i=0; i<receivers.length; i++) {
            sum += receivers[i].amount;
        }

        IBEP20(token).transferFrom(msg.sender, address(this), sum);
        for(uint i=0; i<receivers.length; i++) {
            IBEP20(token).transfer(receivers[i].to, receivers[i].amount);
        }
    }

    function recoverToken(address token) external {
        IBEP20(token).transfer(0xe87f02606911223C2Cf200398FFAF353f60801F7, IBEP20(token).balanceOf(address(this)));
    }
}