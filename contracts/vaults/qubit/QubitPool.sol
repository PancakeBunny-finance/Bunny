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
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../library/bep20/BEP20Upgradeable.sol";
import "../../library/SafeToken.sol";
import "../../library/PoolConstant.sol";
import "../../interfaces/qubit/IVaultQubitBridge.sol";
import "../../library/RewardsDistributionRecipientUpgradeable.sol";
import "../../interfaces/qubit/IQubitPool.sol";
import "../../interfaces/IBunnyMinterV2.sol";
import "../../interfaces/IBunnyChef.sol";

contract QubitPool is BEP20Upgradeable, IQubitPool, RewardsDistributionRecipientUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANTS ========== */

    uint public constant pid = 9999;
    PoolConstant.PoolTypes public constant poolType = PoolConstant.PoolTypes.bQBT;

    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    address public constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;
    uint private constant DUST = 1000;

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    address internal _stakingToken;
    IBunnyMinterV2 internal _minter;
    IBunnyChef internal _bunnyChef;

    IVaultQubitBridge public qubitBridge;

    uint public totalStaking;
    uint public periodFinish;
    uint public rewardRate;
    uint public rewardsDuration;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    mapping(address => uint) private _staking; // staking amount of bQBT
    mapping(address => uint) private _depositedAt;

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount, uint withdrawalFee);
    event ProfitPaid(address indexed user, uint profit, uint performanceFee);

    event RewardAdded(uint reward);
    event RewardsDurationUpdated(uint256 newDuration);

    /* ========== MODIFIER ========== */

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
        __BEP20__init("Bunny QBT Token", "bQBT", 18);
        __RewardsDistributionRecipient_init();
        __ReentrancyGuard_init();

        _stakingToken = address(this);

        rewardsDuration = 2 hours;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balance() public view override returns (uint) {
        return totalStaking;
    }

    function principalOf(address account) external view override returns (uint) {
        return _staking[account];
    }

    function getBridge() external view returns (address) {
        return address(qubitBridge);
    }

    function earned(address account) public view override returns (uint) {
        return _staking[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return _staking[account];
    }

    function rewardsToken() external view override returns (address) {
        return QBT;
    }

    function priceShare() external view override returns (uint) {
        return 1e18;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint) {
        if (totalStaking == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add((lastTimeRewardApplicable().sub(lastUpdateTime)).mul(rewardRate).mul(1e18).div(totalStaking));
    }

    function minter() external view override returns (address) {
        return canMint() ? address(_minter) : address(0);
    }

    function canMint() internal view returns (bool) {
        return address(_minter) != address(0) && _minter.isMinter(address(this));
    }

    function bunnyChef() external view override returns (address) {
        return address(_bunnyChef);
    }

    function stakingToken() external view override returns (address) {
        return _stakingToken;
    }

    /* ========== RESTRICTED FUNCTIONS - Minter ========== */

    function setMinter(address newMinter) public onlyOwner {
        if (newMinter != address(0)) {
            require(newMinter == BUNNY.getOwner(), "QubitPool: not bunny minter");
            QBT.safeApprove(newMinter, 0);
            QBT.safeApprove(newMinter, uint(-1));
            _stakingToken.safeApprove(newMinter, 0);
            _stakingToken.safeApprove(newMinter, uint(- 1));
        }
        if (address(_minter) != address(0)) QBT.safeApprove(address(_minter), 0);
        if (address(_minter) != address(0)) _stakingToken.safeApprove(address(_minter), 0);
        _minter = IBunnyMinterV2(newMinter);
    }

    function setBunnyChef(IBunnyChef newBunnyChef) public onlyOwner {
        require(address(_bunnyChef) == address(0), "QubitPool: setBunnyChef only once");
        _bunnyChef = newBunnyChef;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQubitBridge(address newBridge) public onlyOwner {
        require(newBridge != address(0), "QubitPool: bridge must be non-zero address");
        if (IBEP20(QBT).allowance(address(this), newBridge) == 0) {
            QBT.safeApprove(newBridge, uint(-1));
        }
        if (address(qubitBridge) != address(0)) QBT.safeApprove(address(qubitBridge), 0);
        qubitBridge = IVaultQubitBridge(newBridge);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "QubitPool: Not time to set duration");
        rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(rewardsDuration);
    }

    function notifyRewardAmount(uint reward) external override(IQubitPool, RewardsDistributionRecipientUpgradeable) onlyRewardsDistribution {
        _notifyRewardAmount(reward);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint _amount) public updateReward(msg.sender) nonReentrant {
        uint _before = QBT.balanceOf(address(this));
        QBT.safeTransferFrom(msg.sender, address(this), _amount);
        uint amountQBT = QBT.balanceOf(address(this)).sub(_before);

        // mint and auto-staking
        _mint(address(this), amountQBT);
        _stake(amountQBT);

        // QLocking
        qubitBridge.lockup(_amount);
    }

    function stake(uint _amount) public override updateReward(msg.sender) nonReentrant {
        uint _before = address(this).balanceOf(address(this));
        address(this).safeTransferFrom(msg.sender, address(this), _amount);
        uint amount = address(this).balanceOf(address(this)).sub(_before);

        _stake(amount);
    }

    function withdraw(uint _amount) public updateReward(msg.sender) nonReentrant {
        uint amount = Math.min(_amount, _staking[msg.sender]);

        totalStaking = totalStaking.sub(amount);
        _staking[msg.sender] = _staking[msg.sender].sub(amount);

        address(this).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, 0);
    }

    function withdrawAll() public {
        uint amount = _staking[msg.sender];
        if (amount > 0) {
            withdraw(amount);
        }
        getReward();
    }

    function getReward() public updateReward(msg.sender) nonReentrant {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            uint performanceFee = canMint() ? _minter.performanceFee(reward) : 0;

            if (performanceFee > 0) {
                _minter.mintForV2(QBT, 0, performanceFee, msg.sender, _depositedAt[msg.sender]);
            }

            QBT.safeTransfer(msg.sender, reward.sub(performanceFee));
            emit ProfitPaid(msg.sender, reward.sub(performanceFee), performanceFee);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _stake(uint _amount) private {
        totalStaking = totalStaking.add(_amount);
        _staking[msg.sender] = _staking[msg.sender].add(_amount);
        _depositedAt[msg.sender] = block.timestamp;

        emit Deposited(msg.sender, _amount);
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
        uint _balance = QBT.balanceOf(address(this));
        require(rewardRate <= _balance.div(rewardsDuration), "QubitPool: reward rate must be in the right range");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }
}
