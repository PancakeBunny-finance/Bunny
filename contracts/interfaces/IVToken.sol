// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";


interface IVToken is IBEP20 {
    function underlying() external returns (address);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function totalBorrowsCurrent() external returns (uint);

    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);
    function borrowRatePerBlock() external view returns (uint);
}
