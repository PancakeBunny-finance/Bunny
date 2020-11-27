// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./IBunnyMinter.sol";
import "./interfaces/IStakingRewards.sol";
import "./PancakeSwap.sol";
import "./strategy/IStrategyHelper.sol";

contract BunnyMinter is IBunnyMinter, Ownable, PancakeSwap {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    BEP20 private constant bunny = BEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    address public constant dev = 0xe87f02606911223C2Cf200398FFAF353f60801F7;
    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    uint public WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
    uint public WITHDRAWAL_FEE = 50;
    uint public constant FEE_MAX = 10000;

    uint public PERFORMANCE_FEE = 3000; // 30%

    uint public bunnyPerProfitBNB;
    uint public bunnyPerBunnyBNBFlip;

    address public constant bunnyPool = 0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D;
    IStrategyHelper public helper = IStrategyHelper(0xA84c09C1a2cF4918CaEf625682B429398b97A1a0);

    mapping (address => bool) private _minters;

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "not minter");
        _;
    }

    constructor() public {
        bunnyPerProfitBNB = 10e18;
        bunnyPerBunnyBNBFlip = 6e18;
        bunny.approve(bunnyPool, uint(~0));
    }

    function transferBunnyOwner(address _owner) external onlyOwner {
        Ownable(address(bunny)).transferOwnership(_owner);
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

    function setMinter(address minter, bool canMint) external onlyOwner {
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
        require(address(_helper) != address(0), "zero address");
        helper = _helper;
    }

    function isMinter(address account) override view public returns(bool) {
        if (bunny.getOwner() != address(this)) {
            return false;
        }

        if (block.timestamp < 1605585600) { // 12:00 SGT 17th November 2020
            return false;
        }
        return _minters[account];
    }

    function amountBunnyToMint(uint bnbProfit) override view public returns(uint) {
        return bnbProfit.mul(bunnyPerProfitBNB).div(1e18);
    }

    function amountBunnyToMintForBunnyBNB(uint amount, uint duration) override view public returns(uint) {
        return amount.mul(bunnyPerBunnyBNBFlip).mul(duration).div(365 days).div(1e18);
    }

    function withdrawalFee(uint amount, uint depositedAt) override view external returns(uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) override view public returns(uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    function mintFor(address flip, uint _withdrawalFee, uint _performanceFee, address to, uint) override external onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        IBEP20(flip).safeTransferFrom(msg.sender, address(this), feeSum);

        uint bunnyBNBAmount = tokenToBunnyBNB(flip, IBEP20(flip).balanceOf(address(this)));
        address flipToken = bunnyBNBFlipToken();
        IBEP20(flipToken).safeTransfer(bunnyPool, bunnyBNBAmount);
        IStakingRewards(bunnyPool).notifyRewardAmount(bunnyBNBAmount);

        uint contribution = helper.tvlInBNB(flipToken, bunnyBNBAmount).mul(_performanceFee).div(feeSum);
        uint mintBunny = amountBunnyToMint(contribution);
        mint(mintBunny, to);
    }

    function mintForBunnyBNB(uint amount, uint duration, address to) override external onlyMinter {
        uint mintBunny = amountBunnyToMintForBunnyBNB(amount, duration);
        if (mintBunny == 0) return;
        mint(mintBunny, to);
    }

    function mint(uint amount, address to) private {
        bunny.mint(amount);
        bunny.transfer(to, amount);

        uint bunnyForDev = amount.mul(15).div(100);
        bunny.mint(bunnyForDev);
        IStakingRewards(bunnyPool).stakeTo(bunnyForDev, dev);
    }
}