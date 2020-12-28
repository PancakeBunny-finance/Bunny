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

import "../../interfaces/IPancakeRouter02.sol";
import "../../interfaces/IPancakePair.sol";
import "../../interfaces/IMasterChef.sol";
import "../../interfaces/IBunnyMinter.sol";
import "../../interfaces/legacy/IStrategyHelper.sol";
import "../../interfaces/legacy/IStrategyLegacy.sol";

contract StrategyCompoundFLIP is IStrategyLegacy, Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);

    address public keeper = 0x793074D9799DC3c6039F8056F1Ba884a73462051;

    uint public poolId;
    IBEP20 public token;

    address private _token0;
    address private _token1;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) public depositedAt;

    IBunnyMinter public minter;
    IStrategyHelper public helper = IStrategyHelper(0x154d803C328fFd70ef5df52cb027d82821520ECE);

    constructor(uint _pid) public {
        if (_pid != 0) {
            (address _token,,,) = CAKE_MASTER_CHEF.poolInfo(_pid);
            setFlipToken(_token);
            poolId = _pid;
        }

        CAKE.safeApprove(address(ROUTER), 0);
        CAKE.safeApprove(address(ROUTER), uint(~0));
    }

    function setFlipToken(address _token) public onlyOwner {
        require(address(token) == address(0), 'flip token set already');
        token = IBEP20(_token);
        _token0 = IPancakePair(_token).token0();
        _token1 = IPancakePair(_token).token1();

        token.safeApprove(address(CAKE_MASTER_CHEF), uint(~0));

        IBEP20(_token0).safeApprove(address(ROUTER), 0);
        IBEP20(_token0).safeApprove(address(ROUTER), uint(~0));
        IBEP20(_token1).safeApprove(address(ROUTER), 0);
        IBEP20(_token1).safeApprove(address(ROUTER), uint(~0));
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
            token.safeApprove(address(_minter), 0);
            token.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external {
        require(msg.sender == address(_helper) || msg.sender == owner(), 'auth');
        require(address(_helper) != address(0), "zero address");

        helper = _helper;
    }

    function balance() override public view returns (uint) {
        (uint amount,) = CAKE_MASTER_CHEF.userInfo(poolId, address(this));
        return token.balanceOf(address(this)).add(amount);
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

        return helper.profitOf(minter, address(token), _balance.sub(principal));
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(token), balance());
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
        uint _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
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

        CAKE_MASTER_CHEF.deposit(poolId, _amount);
    }

    function deposit(uint _amount) override public {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() override external {
        deposit(token.balanceOf(msg.sender));
    }

    function withdrawAll() override external {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint _before = token.balanceOf(address(this));
        CAKE_MASTER_CHEF.withdraw(poolId, _withdraw);
        uint _after = token.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        uint principal = _principal[msg.sender];
        uint depositTimestamp = depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete depositedAt[msg.sender];

        if (address(minter) != address(0) && minter.isMinter(address(this)) && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            uint withdrawalFee = minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = minter.performanceFee(profit);

            minter.mintFor(address(token), withdrawalFee, performanceFee, msg.sender, depositTimestamp);

            token.safeTransfer(msg.sender, _withdraw.sub(withdrawalFee).sub(performanceFee));
        } else {
            token.safeTransfer(msg.sender, _withdraw);
        }
    }

    function harvest() override external {
        require(msg.sender == keeper || msg.sender == owner(), 'auth');

        CAKE_MASTER_CHEF.withdraw(poolId, 0);
        uint cakeAmount = CAKE.balanceOf(address(this));
        uint cakeForToken0 = cakeAmount.div(2);
        cakeToToken(_token0, cakeForToken0);
        cakeToToken(_token1, cakeAmount.sub(cakeForToken0));
        uint liquidity = generateFlipToken();
        CAKE_MASTER_CHEF.deposit(poolId, liquidity);
    }

    function cakeToToken(address _token, uint amount) private {
        if (_token == address(CAKE)) return;
        address[] memory path;
        if (_token == address(WBNB)) {
            path = new address[](2);
            path[0] = address(CAKE);
            path[1] = _token;
        } else {
            path = new address[](3);
            path[0] = address(CAKE);
            path[1] = address(WBNB);
            path[2] = _token;
        }

        ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
    }

    function generateFlipToken() private returns(uint liquidity) {
        uint amountADesired = IBEP20(_token0).balanceOf(address(this));
        uint amountBDesired = IBEP20(_token1).balanceOf(address(this));

        (,,liquidity) = ROUTER.addLiquidity(_token0, _token1, amountADesired, amountBDesired, 0, 0, address(this), block.timestamp);

        // send dust
        IBEP20(_token0).safeTransfer(msg.sender, IBEP20(_token0).balanceOf(address(this)));
        IBEP20(_token1).safeTransfer(msg.sender, IBEP20(_token1).balanceOf(address(this)));
    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}