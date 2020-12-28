// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ICakeVault {
    function priceShare() external view returns(uint);
    function balanceOf(address account) external view returns(uint);
    function sharesOf(address account) external view returns(uint);
    function deposit(uint _amount) external;
    function withdraw(uint256 _amount) external;
}