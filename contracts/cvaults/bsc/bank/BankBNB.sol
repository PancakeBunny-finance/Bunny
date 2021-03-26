// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../../../interfaces/IStrategy.sol";
import "../../../vaults/VaultController.sol";

import "../../../library/SafeToken.sol";
import "../../interface/IBankBNB.sol";
import "./config/BankConfig.sol";
import "../venus/IStrategyVBNB.sol";


contract BankBNB is IBankBNB, VaultController, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT VARIABLES ========== */

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    uint public constant override pid = 9999;
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.Liquidity;

    /* ========== STATE VARIABLES ========== */

    BankConfig public config;

    uint public glbDebtShare;
    uint public glbDebtVal;
    uint public reservedBNB;
    uint public lastAccrueTime;
    uint public totalShares;

    address public bankETH;
    address public strategyVBNB;

    mapping(address => uint) private _shares;
    mapping(address => uint) private _principals;
    mapping(address => uint) private _depositedAt;
    mapping(address => mapping(address => uint)) private _debtShares;

    /* ========== EVENTS ========== */

    event DebtShareAdded(address indexed pool, address indexed borrower, uint debtShare);
    event DebtShareRemoved(address indexed pool, address indexed borrower, uint debtShare);
    event DebtShareHandedOver(address indexed pool, address indexed borrower, address indexed handOverTo, uint debtShare);

    /* ========== MODIFIERS ========== */

    modifier accrue {
        IStrategyVBNB(strategyVBNB).updateBalance();
        if (now > lastAccrueTime) {
            uint interest = pendingInterest();
            glbDebtVal = glbDebtVal.add(interest);
            reservedBNB = reservedBNB.add(interest.mul(config.getReservePoolBps()).div(10000));
            lastAccrueTime = now;
        }
        _;
        IStrategyVBNB(strategyVBNB).updateBalance();
    }

    modifier onlyBankETH {
        require(msg.sender == bankETH, "BankBNB: caller is not the bankETH");
        _;
    }

    receive() payable external {}

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __VaultController_init(IBEP20(WBNB));
        __ReentrancyGuard_init();
        __Whitelist_init();

        lastAccrueTime = block.timestamp;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalSupply() public view override returns (uint) {
        return totalShares;
    }

    function balance() public view override returns (uint) {
        return totalLiquidity();
    }

    function balanceOf(address account) public view override returns (uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) external view override returns (uint) {
        return Math.min(balanceOf(account), totalLocked());
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) public view override returns (uint) {
        return _principals[account];
    }

    function earned(address account) public view override returns (uint) {
        if (balanceOf(account) >= principalOf(account)) {
            return balanceOf(account).sub(principalOf(account));
        } else {
            return 0;
        }
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function priceShare() external view override returns (uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    /// @dev Return the pending interest that will be accrued in the next call.
    function pendingInterest() public view returns (uint) {
        if (now > lastAccrueTime) {
            uint timePast = block.timestamp.sub(lastAccrueTime);
            uint ratePerSec = config.getInterestRate(glbDebtVal, totalLocked());
            return ratePerSec.mul(glbDebtVal).mul(timePast).div(1e18);
        } else {
            return 0;
        }
    }

    function pendingDebtValOf(address pool, address account) external view override returns (uint) {
        uint debtShare = debtShareOf(pool, account);
        if (glbDebtShare == 0) return debtShare;
        return debtShare.mul(glbDebtVal.add(pendingInterest())).div(glbDebtShare);
    }

    function pendingDebtValOfBankETH() external view returns (uint) {
        uint debtShare = debtShareOf(_unifiedDebtShareKey(), bankETH);
        if (glbDebtShare == 0) return debtShare;
        return debtShare.mul(glbDebtVal.add(pendingInterest())).div(glbDebtShare);
    }

    function debtShareOf(address pool, address account) public view override returns (uint) {
        return _debtShares[pool][account];
    }

    /// @dev Return the total BNB entitled to the token holders. Be careful of unaccrued interests.
    function totalLiquidity() public view returns (uint) {
        return totalLocked().add(glbDebtVal).sub(reservedBNB);
    }

    function totalLocked() public view returns (uint) {
        return IStrategyVBNB(strategyVBNB).wantLockedTotal();
    }

    /// @dev Return the BNB debt value given the debt share. Be careful of unaccrued interests.
    /// @param debtShare The debt share to be converted.
    function debtShareToVal(uint debtShare) public view override returns (uint) {
        if (glbDebtShare == 0) return debtShare;
        // When there's no share, 1 share = 1 val.
        return debtShare.mul(glbDebtVal).div(glbDebtShare);
    }

    /// @dev Return the debt share for the given debt value. Be careful of unaccrued interests.
    /// @param debtVal The debt value to be converted.
    function debtValToShare(uint debtVal) public view override returns (uint) {
        if (glbDebtShare == 0) return debtVal;
        // When there's no share, 1 share = 1 val.
        return debtVal.mul(glbDebtShare).div(glbDebtVal);
    }

    function getUtilizationInfo() external view override returns (uint liquidity, uint utilized) {
        liquidity = totalLiquidity();
        utilized = glbDebtVal;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint) external payable override accrue nonReentrant {
        uint liquidity = totalLiquidity();
        uint share = liquidity == 0 ? msg.value : msg.value.mul(totalShares).div(liquidity);

        totalShares = totalShares.add(share);
        _shares[msg.sender] = _shares[msg.sender].add(share);
        _principals[msg.sender] = _principals[msg.sender].add(msg.value);

        uint bnbAmount = address(this).balance;
        if (bnbAmount > 0) {
            IStrategyVBNB(strategyVBNB).deposit{value : bnbAmount}();
        }

        // TODO: @hc
//        _bunnyChef.notifyDeposited(msg.sender, share);
        _depositedAt[msg.sender] = block.timestamp;
        emit Deposited(msg.sender, msg.value);
    }

    function depositAll() external override {
        revert("N/A");
    }

    function withdraw(uint shares) public override accrue nonReentrant {
        uint withdrawAmount = balance().mul(shares).div(totalShares);
        uint _earned = earned(msg.sender);
        require(totalLocked() >= withdrawAmount, "BankBNB: Not enough balance to withdraw");

        // TODO: @hc
//        _bunnyChef.notifyWithdrawn(msg.sender, shares);
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        uint _before = address(this).balance;
        IStrategyVBNB(strategyVBNB).withdraw(address(this), withdrawAmount);
        uint _after = address(this).balance;
        withdrawAmount = _after.sub(_before);

        if (withdrawAmount <= _earned) {
            _earned = withdrawAmount;
        } else {
            _principals[msg.sender] = _principals[msg.sender].add(_earned).sub(withdrawAmount);
        }

        uint withdrawalFee;
        if (canMint() && _earned > 0) {
            uint depositedTimestamp = _depositedAt[msg.sender];
            withdrawalFee = _minter.withdrawalFee(withdrawAmount.sub(_earned), depositedTimestamp);
            uint performanceFee = _minter.performanceFee(_earned);

            _minter.mintFor{ value: withdrawalFee.add(performanceFee) }(address(0), withdrawalFee, performanceFee, msg.sender, depositedTimestamp);
            emit ProfitPaid(msg.sender, _earned, performanceFee);

            withdrawAmount = withdrawAmount.sub(withdrawalFee).sub(performanceFee);
        }

        SafeToken.safeTransferETH(msg.sender, withdrawAmount);
        emit Withdrawn(msg.sender, withdrawAmount, withdrawalFee);
    }

    function withdrawAll() external override {
        uint shares = sharesOf(msg.sender);
        if (shares > 0) {
            withdraw(shares);
        }
        getReward();
    }

    // @dev add yield to principal, then get $bunny
    function getReward() public override nonReentrant {
        uint _earned = earned(msg.sender);
        if (canMint() && _earned > 0) {
            uint depositTimestamp = _depositedAt[msg.sender];
            uint performanceFee = _minter.performanceFee(_earned);

            uint shares = Math.min(performanceFee.mul(totalShares).div(balance()), sharesOf(msg.sender)); // TODO bugfix
            totalShares = totalShares.sub(shares);
            _shares[msg.sender] = _shares[msg.sender].sub(shares);
            _principals[msg.sender] = _principals[msg.sender].add(_earned).sub(performanceFee);

            _minter.mintFor{ value: performanceFee }(address(0), 0, performanceFee, msg.sender, depositTimestamp);
            emit ProfitPaid(msg.sender, _earned, performanceFee);
        }

        // TODO: @hc
//        uint bunnyAmount = _bunnyChef.safeBunnyTransfer(msg.sender);
//        emit BunnyPaid(msg.sender, bunnyAmount, 0);
    }

    function harvest() external override {
        revert("N/A");
    }

    function accruedDebtValOf(address pool, address account) external override accrue returns (uint) {
        return debtShareToVal(debtShareOf(pool, account));
    }

    /* ========== RESTRICTED FUNCTIONS - CONFIGURATION ========== */

    function setBankETH(address newBankETH) external onlyOwner {
        require(newBankETH != address(0), "BankBNB: invalid bankBNB address");
        require(bankETH == address(0), "BankBNB: bankETH is already set");
        bankETH = newBankETH;
    }

    function setStrategyVBNB(address newStrategyVBNB) external onlyOwner {
        require(newStrategyVBNB != address(0), "BankBNB: invalid strategyVBNB address");
        if (strategyVBNB != address(0)) {
            IStrategyVBNB(strategyVBNB).migrate(payable(newStrategyVBNB));
        }
        strategyVBNB = newStrategyVBNB;
    }

    function updateConfig(address newConfig) external onlyOwner {
        require(newConfig != address(0), "BankBNB: invalid bankConfig address");
        config = BankConfig(newConfig);
    }

    /* ========== RESTRICTED FUNCTIONS - WHITELISTED ========== */

    function borrow(address pool, address borrower, uint debtVal) external override accrue onlyWhitelisted returns (uint debtSharesOfBorrower) {
        debtVal = Math.min(debtVal, totalLocked());
        uint debtShare = debtValToShare(debtVal);

        _debtShares[pool][borrower] = _debtShares[pool][borrower].add(debtShare);
        glbDebtShare = glbDebtShare.add(debtShare);
        glbDebtVal = glbDebtVal.add(debtVal);
        emit DebtShareAdded(pool, borrower, debtShare);
        IStrategyVBNB(strategyVBNB).withdraw(msg.sender, debtVal);
        return debtVal;
    }

    function repay(address pool, address borrower) public payable override accrue onlyWhitelisted returns (uint debtSharesOfBorrower) {
        uint debtShare = Math.min(debtValToShare(msg.value), _debtShares[pool][borrower]);
        if (debtShare > 0) {
            uint debtVal = debtShareToVal(debtShare);
            _debtShares[pool][borrower] = _debtShares[pool][borrower].sub(debtShare);
            glbDebtShare = glbDebtShare.sub(debtShare);
            glbDebtVal = glbDebtVal.sub(debtVal);
            emit DebtShareRemoved(pool, borrower, debtShare);
        }

        uint bnbAmount = address(this).balance;
        if (bnbAmount > 0) {
            IStrategyVBNB(strategyVBNB).deposit{value : bnbAmount}();
        }

        return _debtShares[pool][borrower];
    }

    /* ========== RESTRICTED FUNCTIONS - BANKING ========== */

    function handOverDebtToTreasury(address pool, address borrower) external override accrue onlyBankETH returns (uint debtSharesOfBorrower) {
        uint debtShare = _debtShares[pool][borrower];
        _debtShares[pool][borrower] = 0;
        _debtShares[_unifiedDebtShareKey()][bankETH] = _debtShares[_unifiedDebtShareKey()][bankETH].add(debtShare);

        if (debtShare > 0) {
            emit DebtShareHandedOver(pool, borrower, msg.sender, debtShare);
        }
        return debtShare;
    }

    function repayTreasuryDebt() external payable override accrue onlyBankETH returns (uint debtSharesOfBorrower) {
        return repay(_unifiedDebtShareKey(), bankETH);
    }

    /* ========== RESTRICTED FUNCTIONS - OPERATION ========== */

    function withdrawReservedBNB(address to, uint value) external onlyOwner nonReentrant {
        require(reservedBNB >= value, "BankBNB: value must note exceed reservedBNB");
        reservedBNB = reservedBNB.sub(value);
        IStrategyVBNB(strategyVBNB).withdraw(to, value);
    }

    function distributeReservedBNBToHolders(uint value) external onlyOwner {
        require(reservedBNB >= value, "BankBNB: value must note exceed reservedBNB");
        reservedBNB = reservedBNB.sub(value);
    }

    function recoverToken(address _token, uint amount) external override onlyOwner {
        IBEP20(_token).safeTransfer(owner(), amount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _unifiedDebtShareKey() private view returns (address) {
        return address(this);
    }
}
