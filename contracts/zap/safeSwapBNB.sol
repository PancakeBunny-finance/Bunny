// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../library/SafeToken.sol";
import "../interfaces/IWETH.sol";

contract safeSwapBNB {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;


    /* ========== CONSTRUCTOR ========== */

    constructor() public {}

    receive() external payable {}

    /* ========== FUNCTIONS ========== */

    function withdraw(uint amount) external {
        require(IBEP20(WBNB).balanceOf(msg.sender) >= amount, "Not enough Tokens!");

        IBEP20(WBNB).transferFrom(msg.sender, address(this), amount);

        IWETH(WBNB).withdraw(amount);

        SafeToken.safeTransferETH(msg.sender, amount);

    }
}
