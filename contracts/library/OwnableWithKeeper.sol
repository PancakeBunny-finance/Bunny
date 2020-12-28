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

import "@pancakeswap/pancake-swap-lib/contracts/GSN/Context.sol";


contract OwnableWithKeeper is Context {
    address private _owner;
    address private _keeper;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event KeeperTransferred(address indexed previousKeeper, address indexed newKeeper);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner and keeper.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        _keeper = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
        emit KeeperTransferred(address(0), msgSender);
    }

    /**
      * @dev Returns the address of the current owner.
      */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Returns the address of the current keeper.
     */
    function keeper() public view returns (address) {
        return _keeper;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "OwnableWithKeeper: caller is not the owner");
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner or keeper.
     */
    modifier onlyAuthorized() {
        require(_owner == _msgSender() || _keeper == _msgSender(), "OwnableWithKeeper: caller is not the owner or keeper");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "OwnableWithKeeper: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Transfers keeper of the contract to a new account (`newKeeper`).
     * Can only be called by the current owner or keeper.
     */
    function transferKeeper(address newKeeper) public virtual onlyAuthorized {
        require(newKeeper != address(0), "OwnableWithKeeper: new keeper is the zero address");
        emit KeeperTransferred(_owner, newKeeper);
        _keeper = newKeeper;
    }
}
