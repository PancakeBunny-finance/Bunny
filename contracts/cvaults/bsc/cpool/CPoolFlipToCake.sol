// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../../library/RewardsDistributionRecipientUpgradeable.sol";

import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IMasterChef.sol";
import "../../../interfaces/IBunnyMinter.sol";
import "../../interface/ICPool.sol";

import "../../../vaults/VaultController.sol";
import {PoolConstant} from "../../../library/PoolConstant.sol";


contract CPoolFlipToCake is ICPool, VaultController, IStrategy, RewardsDistributionRecipientUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.FlipToCake;

    /* ========== STATE VARIABLES ========== */

    IStrategy private _rewardsToken;

    uint public periodFinish;
    uint public rewardRate;
    uint public rewardsDuration;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public override rewards;

    uint private _totalSupply;
    mapping(address => uint) private _balances;

    uint public override pid;
    mapping (address => uint) private _depositedAt;

    address public cvaultBSC;

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyCVaultBSC {
        require(msg.sender == cvaultBSC, 'CPoolFlipToCake: caller is not the cvaultBSC');
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint reward);
    event RewardsDurationUpdated(uint newDuration);

    /* ========== INITIALIZER ========== */

    function initialize(uint _pid, address _cvaultBSC) external initializer {
        (address _token,,,) = CAKE_MASTER_CHEF.poolInfo(_pid);
        __VaultController_init(IBEP20(_token));
        __RewardsDistributionRecipient_init();
        __ReentrancyGuard_init();

        _stakingToken.safeApprove(address(CAKE_MASTER_CHEF), uint(~0));

        pid = _pid;

        rewardsDuration = 24 hours;
        rewardsDistribution = msg.sender;
        cvaultBSC = _cvaultBSC;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function balance() override external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function sharesOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function principalOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_rewardsToken);
    }

    function priceShare() external view override returns(uint) {
        return 1e18;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) override public view returns (uint) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(address to, uint amount) external override nonReentrant notPaused updateReward(to) onlyCVaultBSC {
        require(amount > 0, "CPoolFlipToCake: amount must be greater than zero");
        _totalSupply = _totalSupply.add(amount);
        _balances[to] = _balances[to].add(amount);
        _depositedAt[to] = block.timestamp;
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        CAKE_MASTER_CHEF.deposit(pid, amount);
        emit Deposited(to, amount);

        _harvest();
    }

    function deposit(uint) public override {
        revert("N/A");
    }

    function depositAll() override external {
        revert("N/A");
    }

    function withdraw(uint) external override {
        revert("N/A");
    }

    function withdraw(address to, uint amount) public override nonReentrant updateReward(to) onlyCVaultBSC {
        require(amount > 0, "CPoolFlipToCake: amount must be greater than zero");
        _totalSupply = _totalSupply.sub(amount);
        _balances[to] = _balances[to].sub(amount);
        CAKE_MASTER_CHEF.withdraw(pid, amount);
        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(to, amount, 0);

        _harvest();
    }

    function withdrawAll() external override {
        revert("N/A");
    }

    function withdrawAll(address to) external override onlyCVaultBSC {
        uint _withdraw = withdrawableBalanceOf(to);
        if (_withdraw > 0) {
            withdraw(to, _withdraw);
        }
        getReward(to);
    }

    function getReward() external override {
        revert("N/A");
    }

    function getReward(address to) public override nonReentrant updateReward(to) onlyCVaultBSC {
        uint reward = rewards[to];
        if (reward > 0) {
            rewards[to] = 0;
            _rewardsToken.withdraw(reward);
            uint cakeBalance = IBEP20(CAKE).balanceOf(address(this));

            IBEP20(CAKE).safeTransfer(msg.sender, cakeBalance);
            emit ProfitPaid(to, cakeBalance, 0);
        }
    }

    function harvest() public override {
        CAKE_MASTER_CHEF.withdraw(pid, 0);
        _harvest();
    }

    function _harvest() private {
        uint cakeAmount = IBEP20(CAKE).balanceOf(address(this));
        uint _before = _rewardsToken.sharesOf(address(this));
        _rewardsToken.deposit(cakeAmount);
        uint amount = _rewardsToken.sharesOf(address(this)).sub(_before);
        if (amount > 0) {
            _notifyRewardAmount(amount);
            emit Harvested(amount);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinter(IBunnyMinter) override public onlyOwner {
        revert("N/A");
    }

    function setRewardsToken(address newRewardsToken) public onlyOwner {
        require(address(_rewardsToken) == address(0), "CPoolFlipToCake: rewards token already set");

        _rewardsToken = IStrategy(newRewardsToken);
        IBEP20(CAKE).safeApprove(newRewardsToken, 0);
        IBEP20(CAKE).safeApprove(newRewardsToken, uint(~0));
    }

    function notifyRewardAmount(uint reward) public override onlyRewardsDistribution {
        _notifyRewardAmount(reward);
    }

    function _notifyRewardAmount(uint reward) private updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint remaining = periodFinish.sub(block.timestamp);
            uint leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint _balance = _rewardsToken.sharesOf(address(this));
        require(rewardRate <= _balance.div(rewardsDuration), "CPoolFlipToCake: reward rate must be in the right range");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "CPoolFlipToCake: reward duration can only be updated after the period ends");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken) && tokenAddress != _rewardsToken.stakingToken(), "CPoolFlipToCake: cannot recover underlying token");
        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
