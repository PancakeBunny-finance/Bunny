// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

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

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

import "../Timelock.sol";


interface IVault {
    function setMinter(address newMinter) external;
}

interface IBunnyPool {
    function setStakePermission(address _address, bool permission) external;
    function setRewardsDistribution(address _rewardsDistribution) external;
}

contract BunnyMinterMigrator is OwnableUpgradeable {
    address payable public constant TIMELOCK = 0x85c9162A51E03078bdCd08D4232Bab13ed414cC3;
    address private constant BUNNY_POOL = 0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D;
    address private constant MINTER_V1 = 0x0B4A714AAf59E46cb1900E3C031017Fd72667EfE;

    receive() external payable {}
    fallback() external payable {
        require(msg.sender == owner(), "not owner");

        address timelock = TIMELOCK;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := call(gas(), timelock, callvalue(), ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    function migrateMinterV2(address minterV2, uint eta) external onlyOwner {
        Timelock(TIMELOCK).executeTransaction(MINTER_V1, 0, "transferBunnyOwner(address)", abi.encode(minterV2), eta);

        // BUNNY/BNB + 15 farming pools
        address payable[16] memory pools = [
        0xc80eA568010Bca1Ad659d1937E17834972d66e0D,
        0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD,
        0x7eaaEaF2aB59C2c85a17BEB15B110F81b192e98a,
        0x3f139386406b0924eF115BAFF71D0d30CC090Bd5,
        0x1b6e3d394f1D809769407DEA84711cF57e507B99,
        0x92a0f75a0f07C90a7EcB65eDD549Fa6a45a4975C,
        0xC1aAE51746bEA1a1Ec6f17A4f75b422F8a656ee6,
        0xE07BdaAc4573a00208D148bD5b3e5d2Ae4Ebd0Cc,
        0xa59EFEf41040e258191a4096DC202583765a43E7,
        0xa5B8cdd3787832AdEdFe5a04bF4A307051538FF2,
        0xC0314BbE19D4D5b048D3A3B974f0cA1B2cEE5eF3,
        0x866FD0028eb7fc7eeD02deF330B05aB503e199d4,
        0x0137d886e832842a3B11c568d5992Ae73f7A792e,
        0xCBd4472cbeB7229278F841b2a81F1c0DF1AD0058,
        0xE02BCFa3D0072AD2F52eD917a7b125e257c26032,
        0x41dF17D1De8D4E43d5493eb96e01100908FCcc4f
        ];

        for(uint i=0; i<pools.length; i++) {
            IVault(pools[i]).setMinter(minterV2);
            Ownable(pools[i]).transferOwnership(owner());
        }

        IBunnyPool(BUNNY_POOL).setRewardsDistribution(minterV2);
        IBunnyPool(BUNNY_POOL).setStakePermission(minterV2, true);
        Ownable(BUNNY_POOL).transferOwnership(owner());
        Ownable(minterV2).transferOwnership(TIMELOCK);

        Timelock(TIMELOCK).executeTransaction(TIMELOCK, 0, "setPendingAdmin(address)", abi.encode(owner()), eta);
    }
}
