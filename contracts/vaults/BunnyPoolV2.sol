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
* SOFTWARE.
*/

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../library/SafeToken.sol";

import "../interfaces/IBunnyPool.sol";

import "./VaultController.sol";

contract BunnyPoolV2 is IBunnyPool, VaultController, ReentrancyGuardUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT ========== */

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant MINTER = 0x8cB88701790F650F273c8BB2Cc4c5f439cd65219;
    address public constant FEE_BOX = 0x3749f69B2D99E5586D95d95B6F9B5252C71894bb;

    struct RewardInfo {
        address token;
        uint rewardPerTokenStored;
        uint rewardRate;
        uint lastUpdateTime;
    }

    /* ========== STATE VARIABLES ========== */

    address public rewardsDistribution;

    uint public periodFinish;
    uint public rewardsDuration;
    uint public totalSupply;

    address[] private _rewardTokens;
    mapping(address => RewardInfo) public rewards;
    mapping(address => mapping(address => uint)) public userRewardPerToken;
    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;

    mapping(address => uint) private _balances;

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);

    event RewardsAdded(uint[] amounts);
    event RewardsPaid(address indexed user, address token, uint amount);
    event BunnyPaid(address indexed user, uint profit, uint performanceFee);

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __VaultController_init(IBEP20(BUNNY));
        __ReentrancyGuard_init();

        rewardsDuration = 30 days;
        rewardsDistribution = FEE_BOX;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "BunnyPoolV2: caller is not the rewardsDistribution");
        _;
    }

    modifier updateRewards(address account) {
        for (uint i = 0; i < _rewardTokens.length; i++) {
            RewardInfo storage rewardInfo = rewards[_rewardTokens[i]];
            rewardInfo.rewardPerTokenStored = rewardPerToken(rewardInfo.token);
            rewardInfo.lastUpdateTime = lastTimeRewardApplicable();

            if (account != address(0)) {
                userRewardPerToken[account][rewardInfo.token] = earnedPerToken(account, rewardInfo.token);
                userRewardPerTokenPaid[account][rewardInfo.token] = rewardInfo.rewardPerTokenStored;
            }
        }
        _;
    }

    modifier canStakeTo() {
        require(msg.sender == owner() || msg.sender == MINTER, "BunnyPoolV2: no auth");
        _;
    }

    /* ========== VIEWS ========== */

    function balanceOf(address account) public override view returns (uint) {
        return _balances[account];
    }

    function earned(address account) public override view returns (uint[] memory) {
        uint[] memory pendingRewards = new uint[](_rewardTokens.length);
        for (uint i = 0; i < _rewardTokens.length; i++) {
            pendingRewards[i] = earnedPerToken(account, _rewardTokens[i]);
        }
        return pendingRewards;
    }

    function earnedPerToken(address account, address token) public view returns (uint) {
        return _balances[account].mul(
            rewardPerToken(token).sub(userRewardPerTokenPaid[account][token])
        ).div(1e18).add(userRewardPerToken[account][token]);
    }

    function rewardTokens() public view override returns (address[] memory) {
        return _rewardTokens;
    }

    function rewardPerToken(address token) public view returns (uint) {
        if (totalSupply == 0) return rewards[token].rewardPerTokenStored;
        return rewards[token].rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(rewards[token].lastUpdateTime).mul(rewards[token].rewardRate).mul(1e18).div(totalSupply)
        );
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addRewardsToken(address _rewardsToken) public onlyOwner {
        require(_rewardsToken != address(0), "BunnyPoolV2: BNB uses WBNB address");
        require(rewards[_rewardsToken].token == address(0), "BunnyPoolV2: duplicated rewards token");
        rewards[_rewardsToken] = RewardInfo(_rewardsToken, 0, 0, 0);
        _rewardTokens.push(_rewardsToken);
    }

    function setRewardsDistribution(address _rewardsDistribution) public onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    function setRewardsDuration(uint _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "BunnyPoolV2: invalid rewards duration");
        rewardsDuration = _rewardsDuration;
    }

    function notifyRewardAmounts(uint[] memory amounts) external override onlyRewardsDistribution updateRewards(address(0)) {
        require(amounts.length == _rewardTokens.length, "BunnyPoolV2: invalid length of amounts");
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
            uint _balance;
            if (rewardInfo.token == WBNB) {
                _balance = address(this).balance;
            } else if (rewardInfo.token == BUNNY) {
                _balance = IBEP20(BUNNY).balanceOf(address(this)).sub(totalSupply);
            } else {
                _balance = IBEP20(rewardInfo.token).balanceOf(address(this));
            }

            require(rewardInfo.rewardRate <= _balance.div(rewardsDuration), "BunnyPoolV2: invalid rewards amount");
        }

        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsAdded(amounts);
    }

    function depositOnBehalf(uint _amount, address _to) external override canStakeTo {
        _deposit(_amount, _to);
    }

    /* ========== MUTATE FUNCTIONS ========== */

    function deposit(uint _amount) public override nonReentrant {
        _deposit(_amount, msg.sender);
    }

    function depositAll() public nonReentrant {
        _deposit(IBEP20(_stakingToken).balanceOf(msg.sender), msg.sender);
    }

    function withdraw(uint _amount) public override nonReentrant notPaused updateRewards(msg.sender) {
        require(_amount > 0, "BunnyPoolV2: invalid amount");
        _bunnyChef.notifyWithdrawn(msg.sender, _amount);

        totalSupply = totalSupply.sub(_amount);
        _balances[msg.sender] = _balances[msg.sender].sub(_amount);
        IBEP20(_stakingToken).safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll() external override {
        uint amount = _balances[msg.sender];
        if (amount > 0) {
            withdraw(amount);
        }

        getReward();
    }

    function getReward() public override nonReentrant updateRewards(msg.sender) {
        for (uint i = 0; i < _rewardTokens.length; i++) {
            uint reward = userRewardPerToken[msg.sender][_rewardTokens[i]];
            if (reward > 0) {
                userRewardPerToken[msg.sender][_rewardTokens[i]] = 0;

                if (_rewardTokens[i] == WBNB) {
                    SafeToken.safeTransferETH(msg.sender, reward);
                } else {
                    IBEP20(_rewardTokens[i]).safeTransfer(msg.sender, reward);
                }
                emit RewardsPaid(msg.sender, _rewardTokens[i], reward);
            }
        }

        uint bunnyAmount = _bunnyChef.safeBunnyTransfer(msg.sender);
        emit BunnyPaid(msg.sender, bunnyAmount, 0);
    }


    /* ========== PRIVATE FUNCTIONS ========== */

    function _deposit(uint _amount, address _to) private notPaused updateRewards(_to) {
        IBEP20(_stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        _bunnyChef.updateRewardsOf(address(this));

        totalSupply = totalSupply.add(_amount);
        _balances[_to] = _balances[_to].add(_amount);

        _bunnyChef.notifyDeposited(_to, _amount);
        emit Deposited(_to, _amount);
    }
}