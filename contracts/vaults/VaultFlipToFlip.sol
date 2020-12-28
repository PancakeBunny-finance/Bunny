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

import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IMasterChef.sol";
import "../interfaces/IBunnyMinter.sol";
import "./VaultController.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract VaultFlipToFlip is VaultController, IStrategy {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */

    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.FlipToFlip;

    /* ========== STATE VARIABLES ========== */

    uint public override pid;

    address private _token0;
    address private _token1;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) private _depositedAt;

    /* ========== INITIALIZER ========== */

    function initialize(uint _pid) external initializer {
        require(_pid != 0, "VaultFlipToFlip: pid must not be zero");

        (address _token,,,) = CAKE_MASTER_CHEF.poolInfo(_pid);
        __VaultController_init(IBEP20(_token));
        setFlipToken(_token);
        pid = _pid;

        CAKE.safeApprove(address(ROUTER), 0);
        CAKE.safeApprove(address(ROUTER), uint(~0));
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balance() override public view returns (uint) {
        (uint amount,) = CAKE_MASTER_CHEF.userInfo(pid, address(this));
        return _stakingToken.balanceOf(address(this)).add(amount);
    }

    function balanceOf(address account) public view override returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _principal[account];
    }

    function earned(address account) override public view returns (uint) {
        if (balanceOf(account) >= principalOf(account)) {
            return balanceOf(account).sub(principalOf(account));
        } else {
            return 0;
        }
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function priceShare() external view override returns(uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint _amount) public override {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() external override {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function withdrawAll() external override {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint _before = _stakingToken.balanceOf(address(this));
        CAKE_MASTER_CHEF.withdraw(pid, _withdraw);
        uint _after = _stakingToken.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        uint principal = _principal[msg.sender];
        uint depositTimestamp = _depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        uint withdrawalFee;
        if (canMint() && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            withdrawalFee = _minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = _minter.performanceFee(profit);

            _minter.mintFor(address(_stakingToken), withdrawalFee, performanceFee, msg.sender, depositTimestamp);
            emit ProfitPaid(msg.sender, profit, performanceFee);

            _withdraw = _withdraw.sub(withdrawalFee).sub(performanceFee);
        }

        _stakingToken.safeTransfer(msg.sender, _withdraw);
        emit Withdrawn(msg.sender, _withdraw, withdrawalFee);
    }

    function harvest() external override onlyKeeper {
        CAKE_MASTER_CHEF.withdraw(pid, 0);
        uint cakeAmount = CAKE.balanceOf(address(this));
        uint cakeForToken0 = cakeAmount.div(2);
        cakeToToken(_token0, cakeForToken0);
        cakeToToken(_token1, cakeAmount.sub(cakeForToken0));
        uint liquidity = generateFlipToken();
        CAKE_MASTER_CHEF.deposit(pid, liquidity);
        emit Harvested(liquidity);
    }

    function withdraw(uint256 shares) external override onlyWhitelisted {
        uint _withdraw = balance().mul(shares).div(totalShares);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        uint _before = _stakingToken.balanceOf(address(this));
        CAKE_MASTER_CHEF.withdraw(pid, _withdraw);
        uint _after = _stakingToken.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        _stakingToken.safeTransfer(msg.sender, _withdraw);
        emit Withdrawn(msg.sender, _withdraw, 0);
    }

    function getReward() external override {
        revert("N/A");
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function setFlipToken(address _token) private {
        _token0 = IPancakePair(_token).token0();
        _token1 = IPancakePair(_token).token1();

        _stakingToken.safeApprove(address(CAKE_MASTER_CHEF), uint(~0));

        IBEP20(_token0).safeApprove(address(ROUTER), 0);
        IBEP20(_token0).safeApprove(address(ROUTER), uint(~0));
        IBEP20(_token1).safeApprove(address(ROUTER), 0);
        IBEP20(_token1).safeApprove(address(ROUTER), uint(~0));
    }

    function _depositTo(uint _amount, address _to) private notPaused {
        uint _pool = balance();
        uint _before = _stakingToken.balanceOf(address(this));
        _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = _stakingToken.balanceOf(address(this));
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
        _depositedAt[_to] = block.timestamp;

        CAKE_MASTER_CHEF.deposit(pid, _amount);
        emit Deposited(_to, _amount);
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

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken) && tokenAddress != address(CAKE), "VaultFlipToFlip: cannot recover underlying token");
        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
