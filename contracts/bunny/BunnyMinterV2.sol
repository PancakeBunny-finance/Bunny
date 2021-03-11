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

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../interfaces/IBunnyMinterV2.sol";
import "../interfaces/legacy/IStakingRewards.sol";
import "./PancakeSwapV2.sol";
import "../interfaces/legacy/IStrategyHelper.sol";

contract BunnyMinterV2 is IBunnyMinterV2, PancakeSwapV2 {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    BEP20 private constant BUNNY_TOKEN = BEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    address public constant BUNNY_POOL = 0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D;
    address public constant DEPLOYER = 0xe87f02606911223C2Cf200398FFAF353f60801F7;
    address private constant BUNNY_BNB_FLIP = 0x7Bb89460599Dbf32ee3Aa50798BBcEae2A5F7f6a;
    address private constant TIMELOCK = 0x85c9162A51E03078bdCd08D4232Bab13ed414cC3;

    uint public constant FEE_MAX = 10000;

    /* ========== STATE VARIABLES ========== */

    address public bunnyChef;
    mapping (address => bool) private _minters;
    IStrategyHelper public helper;

    uint public PERFORMANCE_FEE;
    uint public override WITHDRAWAL_FEE_FREE_PERIOD;
    uint public override WITHDRAWAL_FEE;

    uint public override bunnyPerProfitBNB;
    uint public bunnyPerBunnyBNBFlip;   // will be deprecated

    /* ========== MODIFIERS ========== */

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "BunnyMinterV2: caller is not the minter");
        _;
    }

    modifier onlyBunnyChef {
        require(msg.sender == bunnyChef, "BunnyMinterV2: caller not the bunny chef");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __PancakeSwapV2_init();

        WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
        WITHDRAWAL_FEE = 50;
        PERFORMANCE_FEE = 3000;

        bunnyPerProfitBNB = 5e18;
        bunnyPerBunnyBNBFlip = 6e18;

        helper = IStrategyHelper(0xA84c09C1a2cF4918CaEf625682B429398b97A1a0);
        BUNNY_TOKEN.approve(BUNNY_POOL, uint(-1));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferBunnyOwner(address _owner) external onlyOwner {
        Ownable(address(BUNNY_TOKEN)).transferOwnership(_owner);
    }

    function setWithdrawalFee(uint _fee) external onlyOwner {
        require(_fee < 500, "wrong fee");   // less 5%
        WITHDRAWAL_FEE = _fee;
    }

    function setPerformanceFee(uint _fee) external onlyOwner {
        require(_fee < 5000, "wrong fee");
        PERFORMANCE_FEE = _fee;
    }

    function setWithdrawalFeeFreePeriod(uint _period) external onlyOwner {
        WITHDRAWAL_FEE_FREE_PERIOD = _period;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    function setBunnyPerProfitBNB(uint _ratio) external onlyOwner {
        bunnyPerProfitBNB = _ratio;
    }

    function setBunnyPerBunnyBNBFlip(uint _bunnyPerBunnyBNBFlip) external onlyOwner {
        bunnyPerBunnyBNBFlip = _bunnyPerBunnyBNBFlip;
    }

    function setHelper(IStrategyHelper _helper) external onlyOwner {
        require(address(_helper) != address(0), "BunnyMinterV2: helper can not be zero");
        helper = _helper;
    }

    function setBunnyChef(address _bunnyChef) external onlyOwner {
        require(bunnyChef == address(0), "BunnyMinterV2: setBunnyChef only once");
        bunnyChef = _bunnyChef;
    }

    /* ========== VIEWS ========== */

    function isMinter(address account) override public view returns(bool) {
        if (BUNNY_TOKEN.getOwner() != address(this)) {
            return false;
        }
        return _minters[account];
    }

    function amountBunnyToMint(uint bnbProfit) override public view returns(uint) {
        return bnbProfit.mul(bunnyPerProfitBNB).div(1e18);
    }

    function amountBunnyToMintForBunnyBNB(uint amount, uint duration) override public view returns(uint) {
        return amount.mul(bunnyPerBunnyBNBFlip).mul(duration).div(365 days).div(1e18);
    }

    function withdrawalFee(uint amount, uint depositedAt) override external view returns(uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) override public view returns(uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    /* ========== V1 FUNCTIONS ========== */

    function mintFor(address flip, uint _withdrawalFee, uint _performanceFee, address to, uint) override external onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        IBEP20(flip).safeTransferFrom(msg.sender, address(this), feeSum);

        uint bunnyBNBAmount = tokenToBunnyBNB(flip, IBEP20(flip).balanceOf(address(this)));
        if (bunnyBNBAmount == 0) return;

        IBEP20(BUNNY_BNB_FLIP).safeTransfer(BUNNY_POOL, bunnyBNBAmount);
        IStakingRewards(BUNNY_POOL).notifyRewardAmount(bunnyBNBAmount);

        uint contribution = helper.tvlInBNB(BUNNY_BNB_FLIP, bunnyBNBAmount).mul(_performanceFee).div(feeSum);
        uint mintBunny = amountBunnyToMint(contribution);
        if (mintBunny == 0) return;
        _mint(mintBunny, to);
    }

    // @dev will be deprecated
    function mintForBunnyBNB(uint amount, uint duration, address to) override external onlyMinter {
        uint mintBunny = amountBunnyToMintForBunnyBNB(amount, duration);
        if (mintBunny == 0) return;
        _mint(mintBunny, to);
    }

    /* ========== V2 FUNCTIONS ========== */

    function mint(uint amount) external override onlyBunnyChef {
        if (amount == 0) return;
        _mint(amount, address(this));
    }

    function safeBunnyTransfer(address _to, uint _amount) external override onlyBunnyChef {
        if (_amount == 0) return;

        uint256 bal = BUNNY_TOKEN.balanceOf(address(this));
        if (_amount <= bal) {
            IBEP20(BUNNY).safeTransfer(_to, _amount);
        } else {
            IBEP20(BUNNY).safeTransfer(_to, bal);
        }
    }

    // @dev should be called when determining mint in governance. Bunny is transferred to the timelock contract.
    function mintGov(uint amount) external override onlyOwner {
        if (amount == 0) return;
        _mint(amount, TIMELOCK);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _mint(uint amount, address to) private {
        BUNNY_TOKEN.mint(amount);
        if (to != address(this)) {
            BUNNY_TOKEN.transfer(to, amount);
        }

        uint bunnyForDev = amount.mul(15).div(100);
        BUNNY_TOKEN.mint(bunnyForDev);
        IStakingRewards(BUNNY_POOL).stakeTo(bunnyForDev, DEPLOYER);
    }
}
