// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../library/RewardsDistributionRecipientUpgradeable.sol";
import "../library/PausableUpgradeable.sol";

import "../interfaces/IPriceCalculator.sol";
import "../interfaces/IPresaleLocker.sol";


contract VaultQBTBNB is IPresaleLocker, RewardsDistributionRecipientUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ========== */

    address public constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526; // QBT
    IBEP20 public constant stakingToken = IBEP20(0x67EFeF66A55c4562144B9AcfCFbc62F9E4269b3e); // QBT-BNB
    IPriceCalculator public constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);

    /* ========== STATE VARIABLES ========== */

    IBEP20 public rewardsToken;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== PRESALE ========== */

    mapping(address => uint256) private _presaleBalances;
    uint256 public presaleEndTime; //1626652800 2021-07-19 00:00:00 UTC
    address public presaleContract;

    /* ========== MODIFIERS ========== */

    modifier onlyPresale {
        require(msg.sender == presaleContract, "VaultQBTBNB: no presale contract");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __RewardsDistributionRecipient_init();
        __ReentrancyGuard_init();
        __PausableUpgradeable_init();

        periodFinish = 0;
        rewardRate = 0;
        rewardsDuration = 30 days;

        rewardsDistribution = msg.sender;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balance() external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) override external view returns (uint256) {
        return _balances[account];
    }

    function principalOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function presaleBalanceOf(address account) external view returns (uint256) {
        return _presaleBalances[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        if (block.timestamp <= presaleEndTime) {
            return 0;
        }

        if (block.timestamp > presaleEndTime + 3 days) {
            return _balances[account];
        } else {
            uint withdrawablePresaleBalance = _presaleBalances[account].mul((block.timestamp).sub(presaleEndTime)).div(rewardsDuration);
            return (_balances[account].add(withdrawablePresaleBalance)).sub(_presaleBalances[account]);
        }
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint256 amount) public {
        _deposit(amount, msg.sender);
    }

    function depositAll() external {
        deposit(stakingToken.balanceOf(msg.sender));
    }

    function withdraw(uint256 amount) override public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "VaultQBTBNB: invalid withdraw amount");
        require(amount <= withdrawableBalanceOf(msg.sender), "VaultQBTBNB: exceed withdrawable balance");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawAll() override external {
        uint _withdraw = withdrawableBalanceOf(msg.sender);
        if (_withdraw > 0) {
            withdraw(_withdraw);
        }
        getReward();
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;

            IBEP20(rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function harvest() external {}

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRewardsToken(address _rewardsToken) external onlyOwner {
        require(address(rewardsToken) == address(0), "VaultQBTBNB: rewards token is already set");

        rewardsToken = IBEP20(_rewardsToken);
    }

    function notifyRewardAmount(uint256 reward) override external onlyRewardsDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint _balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= _balance.div(rewardsDuration), "VaultQBTBNB: reward");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);

        emit RewardAdded(reward);
    }

    function setPresale(address _presaleContract) external override onlyOwner {
        presaleContract = _presaleContract;
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "VaultQBTBNB: period");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setPresaleEndTime(uint _endTime) external override onlyPresale {
        presaleEndTime = _endTime;
    }

    //presale --> pool
    function depositBehalf(address account, uint amount) external override onlyPresale {
        require(_balances[account] == 0, "VaultQBTBNB: already set");
        require(amount > 0, "VaultQBTBNB: invalid stake amount");

        _deposit(amount, account);
        _presaleBalances[account] = _presaleBalances[account].add(amount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _deposit(uint256 amount, address _to) private nonReentrant notPaused updateReward(_to) {
        require(amount > 0, "VaultQBTBNB: invalid deposit amount");
        _totalSupply = _totalSupply.add(amount);
        _balances[_to] = _balances[_to].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(_to, amount);
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(stakingToken), "VaultQBTBNB: invalid address");

        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
