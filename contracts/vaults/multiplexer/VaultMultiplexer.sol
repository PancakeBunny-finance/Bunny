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

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {PoolConstant} from "../../library/PoolConstant.sol";
import "../../interfaces/IPancakePair.sol";
import "../../interfaces/IVaultMultiplexer.sol";
import "../../library/SafeToken.sol";
import "../VaultController.sol";

import "../../interfaces/multiplexer/IQMultiplexer.sol";
import "../../interfaces/multiplexer/IQPositionManager.sol";
import "../../interfaces/IPriceCalculator.sol";

contract VaultMultiplexer is VaultController, IVaultMultiplexer, ReentrancyGuardUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    PoolConstant.PoolTypes public constant poolType = PoolConstant.PoolTypes.Multiplexer;

    uint private constant MAX_ITER = 100;
    uint private constant DUST = 1000;
    uint public constant MAX_POSITION_COUNT = 10;
    IPriceCalculator private constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);

    /* ========== STATE VARIABLES ========== */

    address private _token0;
    address private _token1;

    mapping(uint => PositionInfo) private positions;    // id -> positionInfo
    mapping(address => UserInfo) private users;   // account -> userInfo

    IQMultiplexer private qMultiplexer;
    IQPositionManager private positionManager;

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize(address _token) external initializer {
        __ReentrancyGuard_init();
        __VaultController_init(IBEP20(_token));

        _token0 = IPancakePair(_token).token0();
        _token1 = IPancakePair(_token).token1();
    }

    /* ========== MODIFIER ========== */

    modifier onlyPositionOwner(uint id) {
        require(getPositionOwner(id) == msg.sender, "VaultMultiplexer: permission denied");
        _;
    }

    modifier onlyEOACaller() {
        require(msg.sender == tx.origin, "VaultMultiplexer: only EOA can be caller");
        _;
    }

    /* ========== VIEW FUNCTION ========== */

    function balance() public override view returns (uint) {
        return positionManager.positionBalanceOfUser(address(this), address(_stakingToken));
    }

    function balanceOf(uint id) public override view returns (uint) {
        return positionManager.balanceOf(address(_stakingToken), id);
    }

    function principalOf(uint id) public override view returns (uint) {
        return positionManager.principalOf(address(_stakingToken), id);
    }

    function earned(uint id) public override view returns (uint) {
        return positionManager.earned(address(_stakingToken), id);
    }

    function debtRatioLimit() public view returns (uint) {
        return positionManager.debtRatioLimit(address(_stakingToken));
    }

    function debtRatioOf(uint id) external override view returns (uint) {
        return positionManager.debtRatioOf(address(_stakingToken), id);
    }

    function debtValOfPosition(uint id) public override view returns (uint[] memory) {
        return positionManager.debtValOfPosition(address(_stakingToken), id);
    }

    function debtShareOfPosition(uint id, address token) public view returns (uint) {
        return positionManager.debtShareOfPosition(address(_stakingToken), id, token);
    }

    function debtValToShare(uint amount, address token) external view returns (uint) {
        uint totalDebt = positionManager.debtValOfUser(address(this), token);
        return totalDebt == 0 ? amount : amount.mul(positionManager.debtShareOfUser(address(this), token)).div(totalDebt);
    }

    function getPositions(address account) public view returns (uint[] memory) {
        return users[account].positionList;
    }

    function getPositionOwner(uint id) public override view returns (address) {
        return positions[id].account;
    }

    function token0() external override view returns (address) {
        return _token0;
    }

    function token1() external override view returns (address) {
        return _token1;
    }

    function getQubitMultiplexer() external view returns (address) {
        return address(qMultiplexer);
    }

    function getQubitPositionManager() external view returns (address) {
        return address(positionManager);
    }

    function getPositionInfoByAccount(address account) external view returns (PositionState[] memory){
        uint[] memory positionList = getPositions(account);
        PositionState[] memory info;
        if (positionList.length > 0) {
            info = new PositionState[](positionList.length) ;
            for (uint i=0; i<positionList.length; i++){
                uint id = positionList[i];
                IQPositionManager.PositionState memory positionInfo = positionManager.getPositionInfo(address(_stakingToken), id);
                (,uint[] memory liquidationRefund) = positionManager.getLiquidationInfo(address(_stakingToken), id);
                info[i].account = account;
                info[i].liquidated = positionInfo.liquidated;
                info[i].balance = positionInfo.balance;
                info[i].principal = positionInfo.principal;
                info[i].earned = positionInfo.earned;
                info[i].debtRatio = positionInfo.debtRatio;
                info[i].debtToken0 = positionInfo.debtToken0;
                info[i].debtToken1 = positionInfo.debtToken1;
                info[i].token0Value = positionInfo.token0Value;
                info[i].token1Value = positionInfo.token1Value;
                info[i].token0Refund = liquidationRefund[0];
                info[i].token1Refund = liquidationRefund[1];
                info[i].debtRatioLimit = debtRatioLimit();
                info[i].depositedAt = positions[id].depositedAt;
            }
        }
        return info;
    }

    function getVaultState() external view returns (VaultState memory) {
        VaultState memory state;
        (,uint tvlInUSD) = priceCalculator.valueOfAsset(address(_stakingToken), balance());
        state.debtRatioLimit = debtRatioLimit();
        state.balance = balance();
        state.tvl = tvlInUSD;

        return state;
    }

    /* ========== MUTATIVE FUNCTION ========== */

    function openPosition(uint[] memory depositAmount, uint[] memory borrowAmount) external payable onlyEOACaller nonReentrant {
        require(depositAmount.length == 3, "VaultMultiplexer: invalid length of depositAmount");
        require(borrowAmount.length == 2, "VaultMultiplexer: invalid length of borrowAmount");
        if (depositAmount[0] > 0) require(depositAmount[0] == _transferIn(_token0, msg.sender, depositAmount[0]), "VaultMultiplexer: insufficient token0");
        if (depositAmount[1] > 0) require(depositAmount[1] == _transferIn(_token1, msg.sender, depositAmount[1]), "VaultMultiplexer: insufficient token1");
        if (depositAmount[2] > 0) require(depositAmount[2] == _transferIn(address(_stakingToken), msg.sender, depositAmount[2]), "VaultMultiplexer: insufficient stakingToken");

        uint id = positionManager.getLastPositionID(address(_stakingToken));
        PositionInfo storage positionInfo = positions[id];
        UserInfo storage userInfo = users[msg.sender];

        if (_token0 == WBNB || _token1 == WBNB) {
            qMultiplexer.createPosition{value: _token0 == WBNB ? depositAmount[0] : depositAmount[1]}(address(_stakingToken), depositAmount, borrowAmount);
        } else {
            qMultiplexer.createPosition(address(_stakingToken), depositAmount, borrowAmount);
        }

        positionInfo.account = msg.sender;
        positionInfo.depositedAt = block.timestamp;
        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].add(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].add(debtShareOfPosition(id, _token1));
        _appendPosition(msg.sender, id);

        emit OpenPosition(msg.sender, id);
        emit Deposited(msg.sender, id, depositAmount[0], depositAmount[1], depositAmount[2]);
        if (borrowAmount[0] > 0 || borrowAmount[1] > 0) emit Borrow(msg.sender, id, borrowAmount[0], borrowAmount[1]);
    }

    function closePosition(uint id) external onlyEOACaller onlyPositionOwner(id) nonReentrant {
        uint _balance = balanceOf(id);
        UserInfo storage userInfo = users[msg.sender];
        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].sub(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].sub(debtShareOfPosition(id, _token1));

        uint beforeToken0 = _token0 == WBNB ? address(this).balance : IBEP20(_token0).balanceOf(address(this));
        uint beforeToken1 = _token1 == WBNB ? address(this).balance : IBEP20(_token1).balanceOf(address(this));

        qMultiplexer.closePosition(address(_stakingToken), id);

        uint token0Refund = _token0 == WBNB ? address(this).balance.sub(beforeToken0) : IBEP20(_token0).balanceOf(address(this)).sub(beforeToken0);
        uint token1Refund = _token1 == WBNB ? address(this).balance.sub(beforeToken1) : IBEP20(_token1).balanceOf(address(this)).sub(beforeToken1);
        token0Refund = _calcWithdrawalFee(_token0, token0Refund, positions[id].depositedAt);
        token1Refund = _calcWithdrawalFee(_token1, token1Refund, positions[id].depositedAt);

        _removePosition(msg.sender, id);
        delete positions[id];

        _transferOut(_token0, msg.sender, token0Refund);
        _transferOut(_token1, msg.sender, token1Refund);
        emit ClosePosition(msg.sender, id);
        emit Withdrawn(msg.sender, id, _balance, token0Refund, token1Refund);
    }

    function increasePosition(uint id, uint[] memory depositAmount, uint[] memory borrowAmount) external payable onlyEOACaller onlyPositionOwner(id) nonReentrant {
        require(depositAmount.length == 3, "VaultMultiplexer: invalid length of depositAmount");
        require(borrowAmount.length == 2, "VaultMultiplexer: invalid length of borrowAmount");

        UserInfo storage userInfo = users[msg.sender];
        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].sub(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].sub(debtShareOfPosition(id, _token1));

        if (depositAmount[0] > 0) require(depositAmount[0] == _transferIn(_token0, msg.sender, depositAmount[0]), "VaultMultiplexer: insufficient token0");
        if (depositAmount[1] > 0) require(depositAmount[1] == _transferIn(_token1, msg.sender, depositAmount[1]), "VaultMultiplexer: insufficient token1");
        if (depositAmount[2] > 0) require(depositAmount[2] == _transferIn(address(_stakingToken), msg.sender, depositAmount[2]), "VaultMultiplexer: insufficient stakingToken");

        if (_token0 == WBNB || _token1 == WBNB){
            qMultiplexer.increasePosition{value: _token0 == WBNB ? depositAmount[0] : depositAmount[1]}(address(_stakingToken), id, depositAmount, borrowAmount);
        } else {
            qMultiplexer.increasePosition(address(_stakingToken), id, depositAmount, borrowAmount);
        }

        positions[id].depositedAt = block.timestamp;
        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].add(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].add(debtShareOfPosition(id, _token1));

        emit Deposited(msg.sender, id, depositAmount[0], depositAmount[1], depositAmount[2]);
        if (borrowAmount[0] > 0 || borrowAmount[1] > 0) emit Borrow(msg.sender, id, borrowAmount[0], borrowAmount[1]);
    }

    function reducePosition(uint id, uint amount, uint[] memory repayAmount) external onlyEOACaller onlyPositionOwner(id) nonReentrant {
        require(repayAmount.length == 2, "VaultMultiplexer: invalid length of repayAmount");

        {
            uint[] memory debtValue = debtValOfPosition(id);
            require(amount <= principalOf(id), "VaultMultiplexer: VaultMultiplexer: invalid withdrawAmount");
            require(repayAmount[0] <= debtValue[0], "VaultMultiplexer: invalid token0RepayAmount");
            require(repayAmount[1] <= debtValue[1], "VaultMultiplexer: invalid token1RepayAmount");
        }

        uint _depositTimestamp = positions[id].depositedAt;
        UserInfo storage userInfo = users[msg.sender];
        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].sub(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].sub(debtShareOfPosition(id, _token1));

        uint beforeToken0 = _token0 == WBNB ? address(this).balance : IBEP20(_token0).balanceOf(address(this));
        uint beforeToken1 = _token1 == WBNB ? address(this).balance : IBEP20(_token1).balanceOf(address(this));
        qMultiplexer.reducePosition(address(_stakingToken), id, amount, repayAmount);

        userInfo.debtShare[_token0] = userInfo.debtShare[_token0].add(debtShareOfPosition(id, _token0));
        userInfo.debtShare[_token1] = userInfo.debtShare[_token1].add(debtShareOfPosition(id, _token1));

        uint token0Refund = _token0 == WBNB ? address(this).balance.sub(beforeToken0) : IBEP20(_token0).balanceOf(address(this)).sub(beforeToken0);
        uint token1Refund = _token1 == WBNB ? address(this).balance.sub(beforeToken1) : IBEP20(_token1).balanceOf(address(this)).sub(beforeToken1);

        token0Refund = _calcWithdrawalFee(_token0, token0Refund, _depositTimestamp);
        token1Refund = _calcWithdrawalFee(_token1, token1Refund, _depositTimestamp);

        _transferOut(_token0, msg.sender, token0Refund);
        _transferOut(_token1, msg.sender, token1Refund);

        emit Withdrawn(msg.sender, id, amount, token0Refund, token1Refund);
        if (repayAmount[0] > 0 || repayAmount[1] > 0) emit Repay(msg.sender, id, repayAmount[0], repayAmount[1]);
    }

    function refundLiquidation(uint id) external onlyPositionOwner(id) nonReentrant {
        (bool liquidated, uint[] memory refundAmount) = positionManager.getLiquidationInfo(address(_stakingToken), id);
        require(liquidated, "VaultMultiplexer:: not liquidated yet!");

        delete positions[id];
        _removePosition(msg.sender, id);
        qMultiplexer.liquidationRefund(address(_stakingToken), id);
        _transferOut(_token0, msg.sender, refundAmount[0]);
        _transferOut(_token1, msg.sender, refundAmount[1]);
    }

    function getReward(uint id) external onlyPositionOwner(id) nonReentrant {
        uint reward = earned(id);
        if (reward > 0) {
            uint _before = _stakingToken.balanceOf(address(this));
            qMultiplexer.getReward(address(_stakingToken), id);
            reward = _stakingToken.balanceOf(address(this)).sub(_before);

            _transferOut(address(_stakingToken), msg.sender, reward);

            emit ClaimReward(msg.sender, id, reward);
        }
    }

    /* ========== RESTRICTED FUNCTION ========== */

    function setMultiplexer(address _multiplexer) external onlyOwner {
        qMultiplexer = IQMultiplexer(_multiplexer);

        IBEP20(address(_stakingToken)).safeApprove(_multiplexer, uint(-1));
        IBEP20(_token0).safeApprove(_multiplexer, uint(-1));
        IBEP20(_token1).safeApprove(_multiplexer, uint(-1));
    }

    function setPositionManager(address _positionManager) external onlyOwner {
        positionManager = IQPositionManager(_positionManager);
    }

    function setMinter(address newMinter) public override onlyOwner {
        if (newMinter != address(0)) {
            require(newMinter == BUNNY.getOwner(), "VaultMultiplexer: not bunny minter");
            IBEP20(_token0).safeApprove(newMinter, 0);
            IBEP20(_token0).safeApprove(newMinter, uint(-1));
            IBEP20(_token1).safeApprove(newMinter, 0);
            IBEP20(_token1).safeApprove(newMinter, uint(-1));
        }
        if (address(_minter) != address(0)) IBEP20(_token0).safeApprove(address(_minter), 0);
        if (address(_minter) != address(0)) IBEP20(_token1).safeApprove(address(_minter), 0);
        _minter = IBunnyMinterV2(newMinter);
    }

    /* ========== PRIVATE FUNCTION ========== */

    function _transferIn(address token, address from, uint amount) private returns (uint amountIn) {
        if (token == WBNB) return msg.value;
        uint _before = IBEP20(token).balanceOf(address(this));
        IBEP20(token).safeTransferFrom(from, address(this), amount);
        amountIn = IBEP20(token).balanceOf(address(this)).sub(_before);
    }

    function _transferOut(address token, address to, uint amount) private {
        if (amount > 0){
            token == WBNB ? SafeToken.safeTransferETH(to, amount) : IBEP20(token).safeTransfer(to, amount);
        }
    }

    function _appendPosition(address account, uint id) private {
        UserInfo storage user = users[account];
        require(user.positionList.length + 1 <= MAX_POSITION_COUNT, "VaultMultiplexer: MAX_POSITION_COUNT");
        user.positionList.push(id);
    }

    function _removePosition(address account, uint id) private {
        require(users[account].positionList.length > 0, "VaultMultiplexer: empty position list");
        UserInfo storage user = users[account];

        if (id != user.positionList[user.positionList.length - 1]) {
            uint idx = _findIdx(user.positionList, id);
            for (uint i=idx; i<user.positionList.length - 1; i++) {
                user.positionList[i] = user.positionList[i+1];
            }
        }
        user.positionList.pop();
    }

    function _calcWithdrawalFee(address _token, uint _amount, uint _depositTimestamp) private returns (uint) {
        if (canMint()) {
            uint _withdrawalFee = _minter.withdrawalFee(_amount, _depositTimestamp);
            if (_withdrawalFee > DUST) {
                _token == WBNB ?
                _minter.mintForV2{value: _withdrawalFee}(address(0), _withdrawalFee, 0, msg.sender, _depositTimestamp) :
                _minter.mintForV2(_token, _withdrawalFee, 0, msg.sender, _depositTimestamp);
            }
            _amount = _amount.sub(_withdrawalFee);
        }
        return _amount;
    }

    // suppose array sorted by ascending order
    function _findIdx(uint[] memory arr, uint value) private pure returns (uint) {
        uint arrayLen = arr.length;
        uint iter = 0;
        uint start = 0;
        uint end = arrayLen - 1;
        uint i = arrayLen.div(2);

        while (true) {
            require(iter < MAX_ITER, "VaultMultiplexer: MAX_ITER");
            uint v = arr[i];
            if (v == value) {
                return i;
            }
            else if (v > value) {
                end = i;
                i = i.add(start).div(2);
            }
            else {
                start = i;
                i = i.add(end).div(2);
            }
            iter++;
        }

        return i;
    }
}
