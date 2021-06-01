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

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../../library/PausableUpgradeable.sol";
import "../../library/SafeToken.sol";

import "../../interfaces/IPriceCalculator.sol";


contract VaultCompensation is PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    IPriceCalculator public constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    struct RewardInfo {
        address token;
        uint rewardPerTokenStored;
        uint rewardRate;
        uint lastUpdateTime;
    }

    struct DepositRequest {
        address to;
        uint amount;
    }

    struct UserStatus {
        uint balance;
        uint totalRewardsPaidInUSD;
        uint userTotalRewardsPaidInUSD;
        uint[] pendingRewards;
    }

    /* ========== STATE VARIABLES ========== */

    address public stakingToken;
    address public rewardsDistribution;

    uint public periodFinish;
    uint public rewardsDuration;
    uint public totalRewardsPaidInUSD;

    address[] private _rewardTokens;
    mapping(address => RewardInfo) public rewards;
    mapping(address => mapping(address => uint)) public userRewardPerToken;
    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;

    uint private _totalSupply;
    mapping(address => uint) private _balances;
    mapping(address => uint) private _compensations;

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);

    event RewardsAdded(uint value);
    event RewardsPaid(address indexed user, address token, uint amount);
    event Recovered(address token, uint amount);

    receive() payable external {}

    /* ========== MODIFIERS ========== */

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "onlyRewardsDistribution");
        _;
    }

    modifier updateRewards(address account) {
        for (uint i = 0; i < _rewardTokens.length; i++) {
            RewardInfo storage rewardInfo = rewards[_rewardTokens[i]];
            rewardInfo.rewardPerTokenStored = rewardPerToken(rewardInfo.token);
            rewardInfo.lastUpdateTime = lastTimeRewardApplicable();

            if (account != address(0)) {
                userRewardPerToken[account][rewardInfo.token] = earned(account, rewardInfo.token);
                userRewardPerTokenPaid[account][rewardInfo.token] = rewardInfo.rewardPerTokenStored;
            }
        }
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __PausableUpgradeable_init();
        __ReentrancyGuard_init();

        rewardsDuration = 1 days;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint) {
        return _balances[account];
    }

    function statusOf(address account) public view returns (UserStatus memory) {
        UserStatus memory status;
        status.balance = _balances[account];
        status.totalRewardsPaidInUSD = totalRewardsPaidInUSD;
        status.userTotalRewardsPaidInUSD = _compensations[account];
        status.pendingRewards = new uint[](_rewardTokens.length);
        for (uint i = 0; i < _rewardTokens.length; i++) {
            status.pendingRewards[i] = earned(account, _rewardTokens[i]);
        }
        return status;
    }

    function earned(address account, address token) public view returns (uint) {
        return _balances[account].mul(
            rewardPerToken(token).sub(userRewardPerTokenPaid[account][token])
        ).div(1e18).add(userRewardPerToken[account][token]);
    }

    function rewardTokens() public view returns (address[] memory) {
        return _rewardTokens;
    }

    function rewardPerToken(address token) public view returns (uint) {
        if (totalSupply() == 0) return rewards[token].rewardPerTokenStored;
        return rewards[token].rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(rewards[token].lastUpdateTime).mul(rewards[token].rewardRate).mul(1e18).div(totalSupply())
        );
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setStakingToken(address _stakingToken) public onlyOwner {
        require(stakingToken == address(0), "VaultComp: stakingToken set already");
        stakingToken = _stakingToken;
    }

    function addRewardsToken(address _rewardsToken) public onlyOwner {
        require(_rewardsToken != address(0), "VaultComp: BNB uses WBNB address");
        require(rewards[_rewardsToken].token == address(0), "VaultComp: duplicated rewards token");
        rewards[_rewardsToken] = RewardInfo(_rewardsToken, 0, 0, 0);
        _rewardTokens.push(_rewardsToken);
    }

    function setRewardsDistribution(address _rewardsDistribution) public onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    function depositOnBehalf(uint _amount, address _to) external onlyOwner {
        _deposit(_amount, _to);
    }

    function _deposit(uint _amount, address _to) private updateRewards(_to) {
        require(stakingToken != address(0), "VaultComp: staking token must be set");
        IBEP20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        _totalSupply = _totalSupply.add(_amount);
        _balances[_to] = _balances[_to].add(_amount);
        emit Deposited(_to, _amount);
    }

    function depositOnBehalfBulk(DepositRequest[] memory request) external onlyOwner {
        uint sum;
        for (uint i = 0; i < request.length; i++) {
            sum += request[i].amount;
        }

        _totalSupply = _totalSupply.add(sum);
        IBEP20(stakingToken).safeTransferFrom(msg.sender, address(this), sum);

        for (uint i = 0; i < request.length; i++) {
            address to = request[i].to;
            uint amount = request[i].amount;
            _balances[to] = _balances[to].add(amount);
            emit Deposited(to, amount);
        }
    }

    function updateCompensationsBulk(address[] memory _accounts, uint[] memory _values) external onlyOwner {
        for (uint i = 0; i < _accounts.length; i++) {
            _compensations[_accounts[i]] = _compensations[_accounts[i]].add(_values[i]);
        }
    }

    /* ========== RESTRICTED FUNCTIONS - COMPENSATION ========== */

    function notifyRewardAmounts(uint[] memory amounts) external onlyRewardsDistribution updateRewards(address(0)) {
        uint accRewardsPaidInUSD = 0;
        for (uint i = 0; i < _rewardTokens.length; i++) {
            RewardInfo storage rewardInfo = rewards[_rewardTokens[i]];
            if (block.timestamp >= periodFinish) {
                rewardInfo.rewardRate = amounts[i].div(rewardsDuration);
            } else {
                uint remaining = periodFinish.sub(block.timestamp);
                uint leftover = remaining.mul(rewardInfo.rewardRate);
                rewardInfo.rewardRate = amounts[i].add(leftover).div(rewardsDuration);
            }
            rewardInfo.lastUpdateTime = block.timestamp;

            // Ensure the provided reward amount is not more than the balance in the contract.
            // This keeps the reward rate in the right range, preventing overflows due to
            // very high values of rewardRate in the earned and rewardsPerToken functions;
            // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.

            uint _balance = rewardInfo.token == WBNB ? address(this).balance : IBEP20(rewardInfo.token).balanceOf(address(this));
            require(rewardInfo.rewardRate <= _balance.div(rewardsDuration), "VaultComp: invalid rewards amount");

            (, uint valueInUSD) = priceCalculator.valueOfAsset(rewardInfo.token, amounts[i]);
            accRewardsPaidInUSD = accRewardsPaidInUSD.add(valueInUSD);
        }

        totalRewardsPaidInUSD = totalRewardsPaidInUSD.add(accRewardsPaidInUSD);
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsAdded(accRewardsPaidInUSD);
    }

    function setRewardsDuration(uint _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "VaultComp: invalid rewards duration");
        rewardsDuration = _rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint _amount) public notPaused updateRewards(msg.sender) {
        require(stakingToken != address(0), "VaultComp: staking token must be set");
        IBEP20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);

        _totalSupply = _totalSupply.add(_amount);
        _balances[msg.sender] = _balances[msg.sender].add(_amount);
        emit Deposited(msg.sender, _amount);
    }

    function withdraw(uint _amount) external notPaused updateRewards(msg.sender) {
        require(stakingToken != address(0), "VaultComp: staking token must be set");

        _totalSupply = _totalSupply.sub(_amount);
        _balances[msg.sender] = _balances[msg.sender].sub(_amount);
        IBEP20(stakingToken).safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function getReward() public nonReentrant updateRewards(msg.sender) {
        require(stakingToken != address(0), "VaultComp: staking token must be set");
        for (uint i = 0; i < _rewardTokens.length; i++) {
            if (msg.sender != address(0)) {
                uint reward = userRewardPerToken[msg.sender][_rewardTokens[i]];
                if (reward > 0) {
                    userRewardPerToken[msg.sender][_rewardTokens[i]] = 0;
                    (, uint valueInUSD) = priceCalculator.valueOfAsset(_rewardTokens[i], reward);
                    _compensations[msg.sender] = _compensations[msg.sender].add(valueInUSD);

                    if (_rewardTokens[i] == WBNB) {
                        SafeToken.safeTransferETH(msg.sender, reward);
                    } else {
                        IBEP20(_rewardTokens[i]).safeTransfer(msg.sender, reward);
                    }
                    emit RewardsPaid(msg.sender, _rewardTokens[i], reward);
                }
            }
        }
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address _token, uint amount) external onlyOwner {
        require(stakingToken != address(0), "VaultComp: staking token must be set");
        require(_token != address(stakingToken), "VaultComp: cannot recover underlying token");
        IBEP20(_token).safeTransfer(owner(), amount);
        emit Recovered(_token, amount);
    }
}
