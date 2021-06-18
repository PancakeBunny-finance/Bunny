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

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PotConstant} from "../library/PotConstant.sol";

import "../interfaces/IMasterChef.sol";
import "../vaults/VaultController.sol";
import "../interfaces/IZap.sol";
import "../interfaces/IPriceCalculator.sol";

import "./PotController.sol";

contract PotCakeLover is VaultController, PotController {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT ========== */

    address public constant TIMELOCK_ADDRESS = 0x85c9162A51E03078bdCd08D4232Bab13ed414cC3;

    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    IPriceCalculator private constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);
    IZap private constant ZapBSC = IZap(0xdC2bBB0D33E0e7Dea9F5b98F46EDBaC823586a0C);

    uint private constant WEIGHT_BASE = 1000;

    /* ========== STATE VARIABLES ========== */

    PotConstant.PotState public state;

    uint public pid;
    uint public minAmount;
    uint public maxAmount;
    uint public burnRatio;

    uint private _totalSupply;  // total principal
    uint private _currentSupply;
    uint private _donateSupply;
    uint private _totalHarvested;

    uint private _totalWeight;  // for select winner
    uint private _currentUsers;

    mapping(address => uint) private _available;
    mapping(address => uint) private _donation;

    mapping(address => uint) private _depositedAt;
    mapping(address => uint) private _participateCount;
    mapping(address => uint) private _lastParticipatedPot;

    mapping(uint => PotConstant.PotHistory) private _histories;

    bytes32 private _treeKey;
    uint private _boostDuration;

    /* ========== MODIFIERS ========== */

    modifier onlyValidState(PotConstant.PotState _state) {
        require(state == _state, "BunnyPot: invalid pot state");
        _;
    }

    modifier onlyValidDeposit(uint amount) {
        require(_available[msg.sender] == 0 || _depositedAt[msg.sender] >= startedAt, "BunnyPot: cannot deposit before claim");
        require(amount >= minAmount && amount.add(_available[msg.sender]) <= maxAmount, "BunnyPot: invalid input amount");
        if (_available[msg.sender] == 0) {
            _participateCount[msg.sender] = _participateCount[msg.sender].add(1);
            _currentUsers = _currentUsers.add(1);
        }
        _;
    }

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint amount);
    event Claimed(address indexed user, uint amount);

    /* ========== INITIALIZER ========== */

    function initialize(uint _pid, address _token) external initializer {
        __VaultController_init(IBEP20(_token));

        _stakingToken.safeApprove(address(CAKE_MASTER_CHEF), uint(- 1));
        _stakingToken.safeApprove(address(ZapBSC), uint(- 1));

        pid = _pid;
        burnRatio = 10;
        state = PotConstant.PotState.Cooked;
        _boostDuration = 4 hours;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalValueInUSD() public view returns (uint valueInUSD) {
        (, valueInUSD) = priceCalculator.valueOfAsset(address(_stakingToken), _totalSupply);
    }

    function availableOf(address account) public view returns (uint) {
        return _available[account];
    }

    function weightOf(address _account) public view returns (uint, uint, uint) {
        return (_timeWeight(_account), _countWeight(_account), _valueWeight(_account));
    }

    function depositedAt(address account) public view returns (uint) {
        return _depositedAt[account];
    }

    function winnersOf(uint _potId) public view returns (address[] memory) {
        return _histories[_potId].winners;
    }

    function potInfoOf(address _account) public view returns (PotConstant.PotInfo memory, PotConstant.PotInfoMe memory) {
        (, uint valueInUSD) = priceCalculator.valueOfAsset(address(_stakingToken), 1e18);

        PotConstant.PotInfo memory info;
        info.potId = potId;
        info.state = state;
        info.supplyCurrent = _currentSupply;
        info.supplyDonation = _donateSupply;
        info.supplyInUSD = _currentSupply.add(_donateSupply).mul(valueInUSD).div(1e18);
        info.rewards = _totalHarvested.mul(100 - burnRatio).div(100);
        info.rewardsInUSD = _totalHarvested.mul(100 - burnRatio).div(100).mul(valueInUSD).div(1e18);
        info.minAmount = minAmount;
        info.maxAmount = maxAmount;
        info.avgOdds = _totalWeight > 0 && _currentUsers > 0 ? _totalWeight.div(_currentUsers).mul(100e18).div(_totalWeight) : 0;
        info.startedAt = startedAt;

        PotConstant.PotInfoMe memory infoMe;
        infoMe.wTime = _timeWeight(_account);
        infoMe.wCount = _countWeight(_account);
        infoMe.wValue = _valueWeight(_account);
        infoMe.odds = _totalWeight > 0 ? _calculateWeight(_account).mul(100e18).div(_totalWeight) : 0;
        infoMe.available = availableOf(_account);
        infoMe.lastParticipatedPot = _lastParticipatedPot[_account];
        infoMe.depositedAt = depositedAt(_account);
        return (info, infoMe);
    }

    function potHistoryOf(uint _potId) public view returns (PotConstant.PotHistory memory) {
        return _histories[_potId];
    }

    function boostDuration() external view returns(uint) {
        return _boostDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint amount) public onlyValidState(PotConstant.PotState.Opened) onlyValidDeposit(amount) {
        address account = msg.sender;
        _stakingToken.safeTransferFrom(account, address(this), amount);

        _currentSupply = _currentSupply.add(amount);
        _available[account] = _available[account].add(amount);

        _lastParticipatedPot[account] = potId;
        _depositedAt[account] = block.timestamp;

        bytes32 accountID = bytes32(uint256(account));
        uint weightBefore = getWeight(_getTreeKey(), accountID);
        uint weightCurrent = _calculateWeight(account);
        _totalWeight = _totalWeight.sub(weightBefore).add(weightCurrent);
        setWeight(_getTreeKey(), weightCurrent, accountID);

        _depositAndHarvest(amount);

        emit Deposited(account, amount);
    }

    function stepToNext() public onlyValidState(PotConstant.PotState.Opened) {
        address account = msg.sender;
        uint amount = _available[account];
        require(amount > 0 && _lastParticipatedPot[account] < potId, "BunnyPot: is not participant");

        uint available = Math.min(maxAmount, amount);

        address[] memory winners = potHistoryOf(_lastParticipatedPot[account]).winners;
        for(uint i = 0; i < winners.length; i++) {
            if (winners[i] == account) {
                revert("BunnyPot: winner can't step to next");
            }
        }

        _participateCount[account] = _participateCount[account].add(1);
        _currentUsers = _currentUsers.add(1);
        _currentSupply = _currentSupply.add(available);
        _lastParticipatedPot[account] = potId;
        _depositedAt[account] = block.timestamp;

        bytes32 accountID = bytes32(uint256(account));

        uint weightCurrent = _calculateWeight(account);
        _totalWeight = _totalWeight.add(weightCurrent);
        setWeight(_getTreeKey(), weightCurrent, accountID);

        if (amount > available) {
            _stakingToken.safeTransfer(account, amount.sub(available));
        }
    }

    function withdrawAll() public {
        address account = msg.sender;
        uint amount = _available[account];
        require(amount > 0 && _lastParticipatedPot[account] < potId, "BunnyPot: is not participant");

        delete _available[account];

        _withdrawAndHarvest(amount);
        _stakingToken.safeTransfer(account, amount);

        emit Claimed(account, amount);
    }

    function depositDonation(uint amount) public onlyWhitelisted {
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _donateSupply = _donateSupply.add(amount);
        _donation[msg.sender] = _donation[msg.sender].add(amount);

        _depositAndHarvest(amount);
    }

    function withdrawDonation() public onlyWhitelisted {
        uint amount = _donation[msg.sender];
        _donateSupply = _donateSupply.sub(amount);
        delete _donation[msg.sender];

        _withdrawAndHarvest(amount);
        _stakingToken.safeTransfer(msg.sender, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setAmountMinMax(uint _min, uint _max) external onlyKeeper onlyValidState(PotConstant.PotState.Cooked) {
        minAmount = _min;
        maxAmount = _max;
    }

    function openPot() external onlyKeeper onlyValidState(PotConstant.PotState.Cooked) {
        state = PotConstant.PotState.Opened;
        _overCook();

        potId = potId + 1;
        startedAt = block.timestamp;

        _totalWeight = 0;
        _currentSupply = 0;
        _totalHarvested = 0;
        _currentUsers = 0;

        _treeKey = bytes32(potId);
        createTree(_treeKey);
    }

    function closePot() external onlyKeeper onlyValidState(PotConstant.PotState.Opened) {
        state = PotConstant.PotState.Closed;
        _harvest(_stakingToken.balanceOf(address(this)));
    }

    function overCook() external onlyKeeper onlyValidState(PotConstant.PotState.Closed) {
        state = PotConstant.PotState.Cooked;
        getRandomNumber(_totalWeight);
    }

    function harvest() external onlyKeeper {
        if (_totalSupply == 0) return;
        _withdrawAndHarvest(0);
    }

    function sweep() external onlyOwner {
        (uint staked,) = CAKE_MASTER_CHEF.userInfo(pid, address(this));
        uint balance = _stakingToken.balanceOf(address(this));
        uint extra = balance.add(staked).sub(_totalSupply);

        if (balance < extra) {
            _withdrawStakingToken(extra.sub(balance));
        }
        _stakingToken.safeTransfer(owner(), extra);
    }

    function setBurnRatio(uint _burnRatio) external onlyOwner {
        require(_burnRatio <= 100, "BunnyPot: invalid range");
        burnRatio = _burnRatio;
    }

    function setBoostDuration(uint duration) external onlyOwner {
        _boostDuration = duration;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _depositStakingToken(uint amount) private returns (uint cakeHarvested) {
        uint before = CAKE.balanceOf(address(this));
        if (pid == 0) {
            CAKE_MASTER_CHEF.enterStaking(amount);
            cakeHarvested = CAKE.balanceOf(address(this)).add(amount).sub(before);
        } else {
            CAKE_MASTER_CHEF.deposit(pid, amount);
            cakeHarvested = CAKE.balanceOf(address(this)).sub(before);
        }
    }

    function _withdrawStakingToken(uint amount) private returns (uint cakeHarvested) {
        uint before = CAKE.balanceOf(address(this));
        if (pid == 0) {
            CAKE_MASTER_CHEF.leaveStaking(amount);
            cakeHarvested = CAKE.balanceOf(address(this)).sub(amount).sub(before);
        } else {
            CAKE_MASTER_CHEF.withdraw(pid, amount);
            cakeHarvested = CAKE.balanceOf(address(this)).sub(before);
        }
    }

    function _depositAndHarvest(uint amount) private {
        uint cakeHarvested = _depositStakingToken(amount);
        uint harvestShare = _totalSupply != 0 ? cakeHarvested.mul(_currentSupply.add(_donateSupply).add(_totalHarvested)).div(_totalSupply) : 0;
        _totalHarvested = _totalHarvested.add(harvestShare);
        _totalSupply = _totalSupply.add(harvestShare).add(amount);
        _harvest(cakeHarvested);
    }

    function _withdrawAndHarvest(uint amount) private {
        uint cakeHarvested = _withdrawStakingToken(amount);
        uint harvestShare = _totalSupply != 0 ? cakeHarvested.mul(_currentSupply.add(_donateSupply).add(_totalHarvested)).div(_totalSupply) : 0;
        _totalHarvested = _totalHarvested.add(harvestShare);
        _totalSupply = _totalSupply.add(harvestShare).sub(amount);
        _harvest(cakeHarvested);
    }

    function _harvest(uint amount) private {
        if (amount == 0) return;

        if (pid == 0) {
            CAKE_MASTER_CHEF.enterStaking(amount);
        } else {
            CAKE_MASTER_CHEF.deposit(pid, amount);
        }
    }

    function _overCook() private {
        if (_totalWeight == 0) return;

        uint buyback = _totalHarvested.mul(burnRatio).div(100);
        _totalHarvested = _totalHarvested.sub(buyback);
        uint winnerCount = Math.max(1, _totalHarvested.div(1000e18));


        if (buyback > 0) {
            _withdrawStakingToken(buyback);
            uint beforeBUNNY = BUNNY.balanceOf(address(this));
            ZapBSC.zapInToken(address(_stakingToken), buyback, address(BUNNY));
            BUNNY.safeTransfer(TIMELOCK_ADDRESS, BUNNY.balanceOf(address(this)).sub(beforeBUNNY));
        }

        PotConstant.PotHistory memory history;
        history.potId = potId;
        history.users = _currentUsers;
        history.rewardPerWinner = winnerCount > 0 ? _totalHarvested.div(winnerCount) : 0;
        history.date = block.timestamp;
        history.winners = new address[](winnerCount);

        for (uint i = 0; i < winnerCount; i++) {
            uint rn = uint256(keccak256(abi.encode(_randomness, i))).mod(_totalWeight);
            address selected = draw(_getTreeKey(), rn);

            _available[selected] = _available[selected].add(_totalHarvested.div(winnerCount));
            history.winners[i] = selected;
            delete _participateCount[selected];
        }

        _histories[potId] = history;
    }

    function _calculateWeight(address account) private view returns (uint) {
        if (_depositedAt[account] < startedAt) return 0;

        uint wTime = _timeWeight(account);
        uint wCount = _countWeight(account);
        uint wValue = _valueWeight(account);
        return wTime.mul(wCount).mul(wValue).div(100);
    }

    function _timeWeight(address account) private view returns (uint) {
        if (_depositedAt[account] < startedAt) return 0;

        uint timestamp = _depositedAt[account].sub(startedAt);
        if (timestamp < _boostDuration) {
            return 28;
        } else if (timestamp < _boostDuration.mul(2)) {
            return 24;
        } else if (timestamp < _boostDuration.mul(3)) {
            return 20;
        } else if (timestamp < _boostDuration.mul(4)) {
            return 16;
        } else if (timestamp < _boostDuration.mul(5)) {
            return 12;
        } else {
            return 8;
        }
    }

    function _countWeight(address account) private view returns (uint) {
        uint count = _participateCount[account];
        if (count >= 13) {
            return 40;
        } else if (count >= 9) {
            return 30;
        } else if (count >= 5) {
            return 20;
        } else {
            return 10;
        }
    }

    function _valueWeight(address account) private view returns (uint) {
        uint amount = _available[account];
        uint denom = Math.max(minAmount, 1);
        return Math.min(amount.mul(10).div(denom), maxAmount.mul(10).div(denom));
    }

    function _getTreeKey() private view returns(bytes32) {
        return _treeKey == bytes32(0) ? keccak256("Bunny/MultipleWinnerPot") : _treeKey;
    }
}
