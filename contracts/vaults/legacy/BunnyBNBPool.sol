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

contract BunnyBNBPool is IStrategyLegacy, Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    IBEP20 public token;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) public depositedAt;

    IBunnyMinter public minter;
    IStrategyHelper public helper = IStrategyHelper(0xA84c09C1a2cF4918CaEf625682B429398b97A1a0);

    constructor() public {
    }

    function setFlipToken(address _token) public onlyOwner {
        require(address(token) == address(0), 'flip token set already');
        token = IBEP20(_token);
    }

    function setMinter(IBunnyMinter _minter) external onlyOwner {
        minter = _minter;
        if (address(_minter) != address(0)) {
            token.safeApprove(address(_minter), 0);
            token.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external onlyOwner {
        require(address(_helper) != address(0), "zero address");
        helper = _helper;
    }

    function balance() override public view returns (uint) {
        return token.balanceOf(address(this));
    }

    function balanceOf(address account) override public view returns(uint) {
        return _shares[account];
    }

    function withdrawableBalanceOf(address account) override public view returns (uint) {
        return _shares[account];
    }

    function sharesOf(address account) public view returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _shares[account];
    }

    function profitOf(address account) override public view returns (uint _usd, uint _bunny, uint _bnb) {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return (0, 0, 0);
        }
        return (0, minter.amountBunnyToMintForBunnyBNB(balanceOf(account), block.timestamp.sub(depositedAt[account])), 0);
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(token), balance());
    }

    function apy() override public view returns(uint _usd, uint _bunny, uint _bnb) {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return (0, 0, 0);
        }

        uint amount = 1e18;
        uint bunny = minter.amountBunnyToMintForBunnyBNB(amount, 365 days);
        uint _tvl = helper.tvlInBNB(address(token), amount);
        uint bunnyPrice = helper.tokenPriceInBNB(address(BUNNY));

        return (bunny.mul(bunnyPrice).div(_tvl), 0, 0);
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

    function depositTo(uint256, uint256 _amount, address _to) external {
        require(msg.sender == 0x641414e2a04c8f8EbBf49eD47cc87dccbA42BF07 || msg.sender == owner(), "not presale contract");
        _depositTo(_amount, _to);
    }

    function _depositTo(uint _amount, address _to) private {
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint amount = _shares[_to];
        if (amount != 0 && depositedAt[_to] != 0) {
            uint duration = block.timestamp.sub(depositedAt[_to]);
            mintBunny(amount, duration);
        }

        totalShares = totalShares.add(_amount);
        _shares[_to] = _shares[_to].add(_amount);
        depositedAt[_to] = block.timestamp;
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
        uint depositTimestamp = depositedAt[msg.sender];
        delete depositedAt[msg.sender];

        mintBunny(_withdraw, block.timestamp.sub(depositTimestamp));
        token.safeTransfer(msg.sender, _withdraw);
    }

    function mintBunny(uint amount, uint duration) private {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return;
        }

        minter.mintForBunnyBNB(amount, duration, msg.sender);
    }

    function harvest() override external {

    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}