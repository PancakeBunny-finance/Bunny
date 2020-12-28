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

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

import "../../interfaces/IMasterChef.sol";
import "../../interfaces/IBunnyMinter.sol";
import "../../interfaces/legacy/IStrategyHelper.sol";
import "../../interfaces/legacy/IStrategyLegacy.sol";

contract StrategyCompoundCake is IStrategyLegacy, Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);

    address public keeper = 0x793074D9799DC3c6039F8056F1Ba884a73462051;

    uint public constant poolId = 0;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) public depositedAt;

    IBunnyMinter public minter;
    IStrategyHelper public helper = IStrategyHelper(0x6d3A751f4EE348B10eB375D849d5a2539217be49);

    constructor() public {
        CAKE.safeApprove(address(CAKE_MASTER_CHEF), uint(~0));
    }

    function setKeeper(address _keeper) external {
        require(msg.sender == _keeper || msg.sender == owner(), 'auth');
        require(_keeper != address(0), 'zero address');
        keeper = _keeper;
    }

    function setMinter(IBunnyMinter _minter) external onlyOwner {
        // can zero
        minter = _minter;
        if (address(_minter) != address(0)) {
            CAKE.safeApprove(address(_minter), 0);
            CAKE.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external {
        require(msg.sender == address(_helper) || msg.sender == owner(), 'auth');
        require(address(_helper) != address(0), "zero address");

        helper = _helper;
    }

    function balance() override public view returns (uint) {
        (uint amount,) = CAKE_MASTER_CHEF.userInfo(poolId, address(this));
        return CAKE.balanceOf(address(this)).add(amount);
    }

    function balanceOf(address account) override public view returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) override public view returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _principal[account];
    }

    function profitOf(address account) override public view returns (uint _usd, uint _bunny, uint _bnb) {
        uint _balance = balanceOf(account);
        uint principal = principalOf(account);
        if (principal >= _balance) {
            // something wrong...
            return (0, 0, 0);
        }

        return helper.profitOf(minter, address(CAKE), _balance.sub(principal));
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(CAKE), balance());
    }

    function apy() override public view returns(uint _usd, uint _bunny, uint _bnb) {
        return helper.apy(minter, poolId);
    }

    function info(address account) override external view returns(UserInfo memory) {
        UserInfo memory userInfo;

        userInfo.balance = balanceOf(account);
        userInfo.principal = principalOf(account);
        userInfo.available = withdrawableBalanceOf(account);

        Profit memory profit;
        (uint usd, uint bunny, uint bnb) = profitOf(account);
        profit.usd = usd;
        profit.bunny = bunny;
        profit.bnb = bnb;
        userInfo.profit = profit;

        userInfo.poolTVL = tvl();

        APY memory poolAPY;
        (usd, bunny, bnb) = apy();
        poolAPY.usd = usd;
        poolAPY.bunny = bunny;
        poolAPY.bnb = bnb;
        userInfo.poolAPY = poolAPY;

        return userInfo;
    }

    function priceShare() public view returns(uint) {
        return balance().mul(1e18).div(totalShares);
    }

    function _depositTo(uint _amount, address _to) private {
        uint _pool = balance();
        CAKE.safeTransferFrom(msg.sender, address(this), _amount);
        uint shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalShares)).div(_pool);
        }

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);
        _principal[_to] = _principal[_to].add(_amount);
        depositedAt[_to] = block.timestamp;

        uint balanceOfCake = CAKE.balanceOf(address(this));
        CAKE_MASTER_CHEF.enterStaking(balanceOfCake);
    }

    function deposit(uint _amount) override public {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() override external {
        deposit(CAKE.balanceOf(msg.sender));
    }

    function withdrawAll() override external {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        CAKE_MASTER_CHEF.leaveStaking(_withdraw.sub(CAKE.balanceOf(address(this))));

        uint principal = _principal[msg.sender];
        uint depositTimestamp = depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete depositedAt[msg.sender];

        if (address(minter) != address(0) && minter.isMinter(address(this)) && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            uint withdrawalFee = minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = minter.performanceFee(profit);

            minter.mintFor(address(CAKE), withdrawalFee, performanceFee, msg.sender, depositTimestamp);

            CAKE.safeTransfer(msg.sender, _withdraw.sub(withdrawalFee).sub(performanceFee));
        } else {
            CAKE.safeTransfer(msg.sender, _withdraw);
        }

        CAKE_MASTER_CHEF.enterStaking(CAKE.balanceOf(address(this)));
    }

    function harvest() override external {
        require(msg.sender == keeper || msg.sender == owner(), 'auth');

        CAKE_MASTER_CHEF.leaveStaking(0);
        uint cakeAmount = CAKE.balanceOf(address(this));
        CAKE_MASTER_CHEF.enterStaking(cakeAmount);
    }

    // salvage purpose only
    function withdrawToken(address token, uint amount) external {
        require(msg.sender == keeper || msg.sender == owner(), 'auth');
        require(token != address(CAKE));

        IBEP20(token).safeTransfer(msg.sender, amount);
    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}