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

import "../../library/PausableUpgradeable.sol";
import "../../library/SafeToken.sol";

import "../../interfaces/qubit/IQToken.sol";
import "../../interfaces/qubit/IQore.sol";
import "../../interfaces/qubit/IVaultQubitBridge.sol";
import "../../interfaces/qubit/IVaultQubit.sol";
import "../VaultController.sol";

contract VaultQubit is VaultController, IVaultQubit, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    uint public constant pid = 9999;
    PoolConstant.PoolTypes public constant poolType = PoolConstant.PoolTypes.Qubit;

    IQore private constant QORE = IQore(0xF70314eb9c7Fe7D88E6af5aa7F898b3A162dcd48);
    IBEP20 private constant BUNNY = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    IBEP20 private constant QBT = IBEP20(0x17B7163cf1Dbd286E262ddc68b553D899B93f526);
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    uint private constant DUST = 1000;

    /* ========== STATE VARIABLES ========== */

    IQToken public qToken;
    IVaultQubitBridge public qubitBridge;

    uint public totalShares;
    uint private _totalSupply;

    uint public vaultSupply;
    uint public vaultBorrow;

    // control variables for SAV
    uint public leverageRound; // number of count to increase collateral
    uint public collateralRatioLimitFactor; // the factor to control collateralRatioLimit
    uint public reserveRatioFactor;

    // derived ratio variables i.e. 60% = 6e17
    uint public collateralRatio; // current collateralRatio of this vault. (borrow/supply)
    uint public collateralRatioLimit; // use as collateralRatioLimit
    uint public marketCollateralRatio; // collateralFactor from market

    uint public periodFinish;
    uint public rewardRate;
    uint public rewardsDuration;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    mapping(address => uint) private _shares;
    mapping(address => uint) private _principal;
    mapping(address => uint) private _depositedAt;

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount, uint withdrawalFee);
    event ProfitPaid(address indexed user, uint profit, uint performanceFee);
    event RewardsDurationUpdated(uint256 newDuration);

    event CollateralFactorsUpdated(uint collateralRatioFactor);
    event RewardAdded(uint reward);

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

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize(address _token, address _qToken) external initializer {
        require(_token != address(0), "VaultQubit: invalid token");
        __VaultController_init(IBEP20(_token));
        __ReentrancyGuard_init();

        qToken = IQToken(_qToken);

        leverageRound = 3;
        collateralRatioLimitFactor = 900;

        marketCollateralRatio = QORE.marketInfoOf(address(qToken)).collateralFactor;
        collateralRatio = 0;
        collateralRatioLimit = marketCollateralRatio.mul(collateralRatioLimitFactor).div(1000);

        reserveRatioFactor = 10; // reserve 1% of balance default
        rewardsDuration = 2 hours;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    function totalShare() external view returns (uint) {
        return totalShares;
    }

    function balance() public view override returns (uint) {
        return balanceAvailable().add(vaultSupply).sub(vaultBorrow);
    }

    function balanceAvailable() public view returns (uint) {
        return qubitBridge.availableOf(address(this));
    }

    function balanceReserved() public view returns (uint) {
        return Math.min(balanceAvailable(), balance().mul(reserveRatioFactor).div(1000));
    }

    function balanceSuppliable() public view returns (uint) {
        return balanceAvailable().sub(balanceReserved());
    }

    function balanceOf(address account) public view override returns (uint) {
        return _principal[account];
    }

    function sharesOf(address account) public view returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) public view override returns (uint) {
        return _principal[account];
    }

    function withdrawableBalanceOf(address account) external view override returns (uint) {
        return _principal[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(QBT);
    }

    function priceShare() external view override returns (uint) {
        return 1e18;
    }

    function earned(address account) public view override returns (uint) {
        return principalOf(account).mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint) {
        return
        _totalSupply == 0
        ? rewardPerTokenStored
        : rewardPerTokenStored.add((lastTimeRewardApplicable().sub(lastUpdateTime)).mul(rewardRate).mul(1e18).div(_totalSupply));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQubitBridge(address payable newBridge) public onlyOwner {
        require(newBridge != address(0), "VaultQubit: bridge must be non-zero address");
        require(address(qubitBridge) == address(0), "VaultQubit: bridge must be set once");

        if (_stakingToken.allowance(address(this), address(newBridge)) == 0) {
            _stakingToken.safeApprove(address(newBridge), uint(-1));
        }
        qubitBridge = IVaultQubitBridge(newBridge);

        IVaultQubitBridge.MarketInfo memory market = qubitBridge.infoOf(address(this));
        require(market.token != address(0) && market.qToken != address(0), "VaultQubit: invalid market info");
    }

    function setCollateralFactors(uint _collateralRatioLimitFactor) external onlyOwner {
        require(_collateralRatioLimitFactor < 1000, "VaultQubit: invalid safe collateral ratio factor");

        collateralRatioLimitFactor = _collateralRatioLimitFactor;

        updateQubitFactors();
        emit CollateralFactorsUpdated(_collateralRatioLimitFactor);
    }

    function setReserveRatio(uint _reserveRatioFactor) external onlyOwner {
        require(_reserveRatioFactor < 1000, "VaultQubit: invalid reserve ratio");
        reserveRatioFactor = _reserveRatioFactor;
    }

    function setRewardsDuration(uint _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "VaultQubit: Not time to set duration");
        rewardsDuration = _rewardsDuration;
        if (address(qubitBridge) != address(0)) {
            qubitBridge.updateRewardsDuration(rewardsDuration);
        }
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setMinter(address newMinter) public override onlyOwner {
        if (newMinter != address(0)) {
            require(newMinter == BUNNY.getOwner(), "VaultQubit: not bunny minter");
            QBT.safeApprove(newMinter, 0);
            QBT.safeApprove(newMinter, uint(-1));
            _stakingToken.safeApprove(newMinter, 0);
            _stakingToken.safeApprove(newMinter, uint(- 1));
        }
        if (address(_minter) != address(0)) QBT.safeApprove(address(_minter), 0);
        if (address(_minter) != address(0)) _stakingToken.safeApprove(address(_minter), 0);
        _minter = IBunnyMinterV2(newMinter);
    }

    function increaseCollateral() external onlyKeeper {
        _increaseCollateral(qubitBridge.leverageRoundOf(address(this), leverageRound));
        updateQubitFactors();
    }

    function decreaseCollateral(uint amountMin, uint supply) external payable onlyKeeper {
        updateQubitFactors();

        supply = address(_stakingToken) == WBNB ? msg.value : supply;
        supply = _depositToBridge(supply);

        qubitBridge.supply(balanceSuppliable());
        _decreaseCollateral(amountMin);
        qubitBridge.withdraw(supply, msg.sender);

        updateQubitFactors();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateQubitFactors() public {
        (vaultSupply, vaultBorrow) = qubitBridge.snapshotOf(address(this));
        marketCollateralRatio = QORE.marketInfoOf(address(qToken)).collateralFactor;

        collateralRatio = vaultBorrow == 0 ? 0 : vaultBorrow.mul(1e18).div(vaultSupply);
        collateralRatioLimit = marketCollateralRatio.mul(collateralRatioLimitFactor).div(1000);
    }

    function deposit(uint amount) external payable updateReward(msg.sender) notPaused nonReentrant {
        amount = address(_stakingToken) == WBNB ? msg.value : amount;
        _deposit(amount, msg.sender);
    }

    function depositBehalf(uint amount, address to) external override payable updateReward(to) onlyWhitelisted nonReentrant {
        amount = address(_stakingToken) == WBNB ? msg.value : amount;
        _deposit(amount, to);
    }

    function withdrawAll() external updateReward(msg.sender) {
        updateQubitFactors();
        uint amount = balanceOf(msg.sender);
        uint depositTimestamp = _depositedAt[msg.sender];
        uint available = balanceAvailable();

        if (available < amount) {
            _decreaseCollateral(amount);
            available = balanceAvailable();
        }
        // revert if insufficient liquidity
        require(amount <= available, "VaultQubit: insufficient available");

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        uint withdrawalFee = canMint() ? _minter.withdrawalFee(amount, depositTimestamp) : 0;
        if (withdrawalFee > DUST) {
            qubitBridge.withdraw(withdrawalFee, address(this));
            if (address(_stakingToken) == WBNB) {
                _minter.mintForV2{ value: withdrawalFee }(address(0), withdrawalFee, 0, msg.sender, depositTimestamp);
            } else {
                _minter.mintForV2(address(_stakingToken), withdrawalFee, 0, msg.sender, depositTimestamp);
            }
            amount = amount.sub(withdrawalFee);
        }
        qubitBridge.withdraw(amount, msg.sender);
        getReward();

        if (collateralRatio >= collateralRatioLimit) {
            _decreaseCollateral(0);
        }
        emit Withdrawn(msg.sender, amount, withdrawalFee);
    }

    function withdraw(uint _amount) external updateReward(msg.sender) nonReentrant {
        updateQubitFactors();
        uint amount = Math.min(_amount, principalOf(msg.sender));
        uint depositTimestamp = _depositedAt[msg.sender];
        uint available = balanceAvailable();

        if (available < amount) {
            _decreaseCollateral(amount);
            available = balanceAvailable();
        }
        // revert if insufficient liquidity
        require(amount <= available, "VaultQubit: insufficient available");

        uint shares = totalSupply() == 0 ? 0 : Math.min(amount.mul(totalShares).div(totalSupply()), _shares[msg.sender]);

        // update state variables
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _totalSupply = _totalSupply.sub(amount);
        _principal[msg.sender] = _principal[msg.sender].sub(amount);

        uint withdrawalFee = canMint() ? _minter.withdrawalFee(amount, depositTimestamp) : 0;
        if (withdrawalFee > DUST) {
            qubitBridge.withdraw(withdrawalFee, address(this));
            if (address(_stakingToken) == WBNB) {
                _minter.mintForV2{ value: withdrawalFee }(address(0), withdrawalFee, 0, msg.sender, depositTimestamp);
            } else {
                _minter.mintForV2(address(_stakingToken), withdrawalFee, 0, msg.sender, depositTimestamp);
            }
            amount = amount.sub(withdrawalFee);
        }

        _cleanupIfDustShares();
        qubitBridge.withdraw(amount, msg.sender);

        if (collateralRatio >= collateralRatioLimit) {
            _decreaseCollateral(0);
        }
        emit Withdrawn(msg.sender, amount, withdrawalFee);
    }

    function getReward() public updateReward(msg.sender) nonReentrant {
        updateQubitFactors();
        uint amount = rewards[msg.sender];

        if (amount > 0) {
            rewards[msg.sender] = 0;
            uint performanceFee = canMint() ? _minter.performanceFee(amount) : 0;

            if (performanceFee > 0) {
                _minter.mintForV2(address(QBT), 0, performanceFee, msg.sender, _depositedAt[msg.sender]);
            }
            QBT.safeTransfer(msg.sender, amount.sub(performanceFee));
            emit ProfitPaid(msg.sender, amount.sub(performanceFee), performanceFee);
        }
    }

    function harvest() public notPaused onlyKeeper {
        uint harvestQBT = qubitBridge.harvest();
        if (harvestQBT > 0) {
            _notifyRewardAmount(harvestQBT);
        }
        _increaseCollateral(qubitBridge.leverageRoundOf(address(this), leverageRound));
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _increaseCollateral(uint round) private {
        updateQubitFactors();
        uint suppliable = balanceSuppliable();
        if (suppliable > DUST) {
            qubitBridge.supply(suppliable);
        }

        updateQubitFactors();
        uint borrowable = qubitBridge.borrowableOf(address(this), collateralRatioLimit);
        while (!paused && round > 0 && borrowable > balance().mul(reserveRatioFactor).div(1000)) {
            if (borrowable == 0 || collateralRatio >= collateralRatioLimit) {
                return;
            }

            qubitBridge.borrow(borrowable);
            updateQubitFactors();
            suppliable = balanceSuppliable();
            if (suppliable > DUST) {
                qubitBridge.supply(suppliable);
            }

            updateQubitFactors();
            borrowable = qubitBridge.borrowableOf(address(this), collateralRatioLimit);
            round--;
        }
    }

    function _decreaseCollateral(uint amountMin) private {
        updateQubitFactors();

        uint marketSupply = qToken.totalSupply().mul(qToken.exchangeRate()).div(1e18);
        uint marketLiquidity = marketSupply > qToken.totalBorrow() ? marketSupply.sub(qToken.totalBorrow()) : 0;
        require(marketLiquidity >= amountMin, "VaultQubit: not enough market liquidity");

        if (amountMin != uint(-1) && collateralRatio == 0) {
            qubitBridge.redeemUnderlying(Math.min(vaultSupply, amountMin));
            updateQubitFactors();
        } else {
            uint redeemable = qubitBridge.redeemableOf(address(this), collateralRatioLimit);
            while (vaultBorrow > 0 && redeemable > 0) {
                uint redeemAmount = amountMin > 0 ? Math.min(vaultSupply, Math.min(redeemable, amountMin)) : Math.min(vaultSupply, redeemable);
                qubitBridge.redeemUnderlying(redeemAmount);
                qubitBridge.repayBorrow(Math.min(vaultBorrow, balanceAvailable()));
                updateQubitFactors();

                redeemable = qubitBridge.redeemableOf(address(this), collateralRatioLimit);
                uint available = balanceAvailable().add(redeemable);
                if (collateralRatio <= collateralRatioLimit && available >= amountMin) {
                    uint remain = amountMin > balanceAvailable() ? amountMin.sub(balanceAvailable()) : 0;
                    if (remain > 0) {
                        qubitBridge.redeemUnderlying(Math.min(remain, redeemable));
                    }
                    updateQubitFactors();
                    return;
                }
            }

            if (amountMin == uint(-1) && vaultBorrow == 0) {
                qubitBridge.redeemAll();
                updateQubitFactors();
            }
        }
    }

    function _cleanupIfDustShares() private {
        uint shares = _shares[msg.sender];
        if (shares > 0 && shares < DUST) {
            totalShares = totalShares.sub(shares);
            delete _shares[msg.sender];
        }
    }

    function _deposit(uint _amount, address _to) private {
        updateQubitFactors();

        uint _balance = totalSupply();
        _amount = _depositToBridge(_amount);

        uint shares = totalShares == 0 ? _amount : _amount.mul(totalShares).div(_balance);

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);
        _totalSupply = _totalSupply.add(_amount);
        _principal[_to] = _principal[_to].add(_amount);
        _depositedAt[_to] = block.timestamp;

        emit Deposited(_to, _amount);
    }

    function _depositToBridge(uint amount) private returns (uint) {
        if (address(_stakingToken) == WBNB) {
            qubitBridge.deposit{ value: amount }(address(this), amount);
        } else {
            uint _before = _stakingToken.balanceOf(address(qubitBridge));
            _stakingToken.safeTransferFrom(msg.sender, address(qubitBridge), amount);
            amount = _stakingToken.balanceOf(address(qubitBridge)).sub(_before);
            qubitBridge.deposit(address(this), amount);
        }
        return amount;
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
        require(rewardRate <= _balance.div(rewardsDuration), "VaultQubit: reward rate must be in the right range");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(
            tokenAddress != address(0) && tokenAddress != address(_stakingToken) && tokenAddress != address(qToken) && tokenAddress != address(QBT),
            "VaultQubit: cannot recover token"
        );

        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
