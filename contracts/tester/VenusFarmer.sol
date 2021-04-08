// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVaultVenus {
    function depositBNB() external payable;
    function withdrawAll() external;
    function venusBridge() external returns(address);
}

contract VenusFarmer {
    address private vault;
    address payable private bridge;

    constructor(address _vault) public {
        vault = _vault;
        bridge = payable(IVaultVenus(_vault).venusBridge());
    }

    receive() payable external {
        bridge.transfer(address(this).balance);
    }

    function send() external payable {

    }

    function deposit() external payable {
        IVaultVenus(vault).depositBNB{value: msg.value}();
    }

    function withdrawAll() external {
        IVaultVenus(vault).withdrawAll();
    }
}