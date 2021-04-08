// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./IVToken.sol";


interface IVenusPriceOracle {
    function getUnderlyingPrice(IVToken vToken) external view returns (uint);
}
