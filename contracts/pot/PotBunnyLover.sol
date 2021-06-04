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
import "../interfaces/legacy/IStrategyLegacy.sol";

import "./PotController.sol";

contract PotBunnyLover is VaultController, PotController {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT ========== */

    address public constant TIMELOCK_ADDRESS = 0x85c9162A51E03078bdCd08D4232Bab13ed414cC3;

    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IPriceCalculator private constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);
    IZap private constant ZapBSC = IZap(0xdC2bBB0D33E0e7Dea9F5b98F46EDBaC823586a0C);
    IStrategyLegacy private constant BUNNYPool = IStrategyLegacy(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);

    uint private constant WEIGHT_DURATION = 4 hours;
    uint private constant WEIGHT_BASE = 1000;
    uint public constant WINNER_COUNT = 1;

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

    function initialize() external initializer {
        __VaultController_init(BUNNY);

        _stakingToken.safeApprove(address(ZapBSC), uint(- 1));
        WBNB.safeApprove(address(ZapBSC), uint(- 1));
        _stakingToken.safeApprove(address(BUNNYPool), uint(- 1));

        burnRatio = 10;
        state = PotConstant.PotState.Cooked;
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

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint amount) public onlyValidState(PotConstant.PotState.Opened) onlyValidDeposit(amount) {
        address account = msg.sender;
        _stakingToken.safeTransferFrom(account, address(this), amount);

        _currentSupply = _currentSupply.add(amount);
        _available[account] = _available[account].add(amount);

        _lastParticipatedPot[account] = potId;
        _depositedAt[account] = block.timestamp;
        _totalSupply = _totalSupply.add(amount);

        bytes32 accountID = bytes32(uint256(account));
        uint weightBefore = getWeight(_getTreeKey(), accountID);
        uint weightCurrent = _calculateWeight(account);
        _totalWeight = _totalWeight.sub(weightBefore).add(weightCurrent);
        setWeight(_getTreeKey(), weightCurrent, accountID);

        BUNNYPool.deposit(amount);
        emit Deposited(account, amount);
    }

    function withdrawAll() public {
        address account = msg.sender;
        uint amount = _available[account];
        require(amount > 0 && _lastParticipatedPot[account] < potId, "BunnyPot: is not participant");

        _totalSupply = _totalSupply.sub(amount);
        delete _available[account];

        BUNNYPool.withdraw(amount);

        _stakingToken.safeTransfer(account, amount);

        emit Claimed(account, amount);
    }

    function depositDonation(uint amount) public onlyWhitelisted {
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _totalSupply = _totalSupply.add(amount);
        _donateSupply = _donateSupply.add(amount);
        _donation[msg.sender] = _donation[msg.sender].add(amount);

        BUNNYPool.deposit(amount);
        _harvest();
    }

    function withdrawDonation() public onlyWhitelisted {
        uint amount = _donation[msg.sender];
        _totalSupply = _totalSupply.sub(amount);
        _donateSupply = _donateSupply.sub(amount);
        delete _donation[msg.sender];

        BUNNYPool.withdraw(amount);
        _stakingToken.safeTransfer(msg.sender, amount);
        _harvest();
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
        _currentUsers = 0;
        _totalHarvested = 0;

        _treeKey = bytes32(potId);
        createTree(_getTreeKey());
    }

    function closePot() external onlyKeeper onlyValidState(PotConstant.PotState.Opened) {
        state = PotConstant.PotState.Closed;
    }

    function overCook() external onlyKeeper onlyValidState(PotConstant.PotState.Closed) {
        state = PotConstant.PotState.Cooked;
        getRandomNumber(_totalWeight);
    }

    function harvest() external onlyKeeper {
        if (_totalSupply == 0) return;

        _harvest();
    }

    function sweep() external onlyOwner {
        uint balance = BUNNY.balanceOf(address(this));
        if (balance > _totalSupply) {
            BUNNY.safeTransfer(owner(), balance.sub(_totalSupply));
        }

        uint balanceWBNB = WBNB.balanceOf(address(this));
        if (balanceWBNB > 0) {
            WBNB.safeTransfer(owner(), balanceWBNB);
        }
    }

    function setBurnRatio(uint _burnRatio) external onlyOwner {
        require(_burnRatio <= 100, "BunnyPot: invalid range");
        burnRatio = _burnRatio;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _harvest() private {
        if (_totalSupply == 0) return;
        uint WBNBBefore = WBNB.balanceOf(address(this));
        BUNNYPool.getReward();
        uint balanceWBNB = WBNB.balanceOf(address(this)).sub(WBNBBefore);
        balanceWBNB = balanceWBNB.mul(_currentSupply.add(_donateSupply).add(_totalHarvested)).div(_totalSupply);

        if (balanceWBNB == 0) return;

        uint BUNNYBefore = BUNNY.balanceOf(address(this));
        ZapBSC.zapInToken(address(WBNB), balanceWBNB, address(BUNNY));
        uint balanceBUNNY = BUNNY.balanceOf(address(this)).sub(BUNNYBefore);

        _totalHarvested = _totalHarvested.add(balanceBUNNY);
        _totalSupply = _totalSupply.add(balanceBUNNY);

        BUNNYPool.deposit(balanceBUNNY);
    }

    function _overCook() private {
        if (_totalWeight == 0) return;

        uint winnerCount = Math.min(WINNER_COUNT, _currentUsers);
        uint buyback = _totalHarvested.mul(burnRatio).div(100);
        _totalHarvested = _totalHarvested.sub(buyback);

        if (buyback > 0) {
            BUNNYPool.withdraw(buyback);
            BUNNY.safeTransfer(TIMELOCK_ADDRESS, buyback);
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
        if (timestamp < WEIGHT_DURATION) {
            return 28;
        } else if (timestamp < WEIGHT_DURATION.mul(2)) {
            return 24;
        } else if (timestamp < WEIGHT_DURATION.mul(3)) {
            return 20;
        } else if (timestamp < WEIGHT_DURATION.mul(4)) {
            return 16;
        } else if (timestamp < WEIGHT_DURATION.mul(5)) {
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