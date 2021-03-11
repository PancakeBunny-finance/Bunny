// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../../../library/bep20/BEP20Upgradeable.sol";
import "../../../library/SafeToken.sol";
import "../../../library/Whitelist.sol";
import "../../interface/IBankBNB.sol";
import "./config/BankConfig.sol";
import "../venus/IStrategyVBNB.sol";
import "../../../interfaces/IBunnyChef.sol";


contract BankBNB is IBankBNB, BEP20Upgradeable, ReentrancyGuardUpgradeable, Whitelist {
    using SafeToken for address;
    using SafeBEP20 for IBEP20;

    /* ========== STATE VARIABLES ========== */

    BankConfig public config;
    IBunnyChef public bunnyChef;

    uint public glbDebtShare;
    uint public glbDebtVal;
    uint public reservedBNB;
    uint public lastAccrueTime;

    address public bankETH;
    address public strategyVBNB;

    mapping(address => uint) private _principals;
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

    function initialize(string memory name, string memory symbol, uint8 decimals) external initializer {
        __BEP20__init(name, symbol, decimals);
        __ReentrancyGuard_init();
        __Whitelist_init();

        lastAccrueTime = block.timestamp;
    }

    /* ========== VIEW FUNCTIONS ========== */

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

    /// @dev Return the total BNB entitled to the token holders. Be careful of unaccrued interests.
    function totalLiquidity() public view returns (uint) {
        return totalLocked().add(glbDebtVal).sub(reservedBNB);
    }

    function totalLocked() public view returns (uint) {
        return IStrategyVBNB(strategyVBNB).wantLockedTotal();
    }

    function debtValOf(address pool, address account) external view override returns (uint) {
        return debtShareToVal(debtShareOf(pool, account));
    }

    function debtValOfBankETH() external view returns (uint) {
        return debtShareToVal(debtShareOf(_unifiedDebtShareKey(), bankETH));
    }

    function debtShareOf(address pool, address account) public view override returns (uint) {
        return _debtShares[pool][account];
    }

    function principalOf(address account) public view returns (uint) {
        return _principals[account];
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

    function deposit() external payable accrue nonReentrant {
        uint liquidity = totalLiquidity();
        uint share = liquidity == 0 ? msg.value : msg.value.mul(totalSupply()).div(liquidity);
        _principals[msg.sender] = _principals[msg.sender].add(msg.value);
        _mint(msg.sender, share);

        uint balance = address(this).balance;
        if (balance > 0) {
            IStrategyVBNB(strategyVBNB).deposit{value : balance}();
        }

        bunnyChef.notifyDeposited(msg.sender, share);
    }

    function withdraw(uint share) public accrue nonReentrant {
        if (totalSupply() == 0) return;

        uint bnbAvailable = totalLiquidity() - glbDebtVal;
        uint bnbAmount = share.mul(totalLiquidity()).div(totalSupply());
        require(bnbAvailable >= bnbAmount, "BankBNB: Not enough balance to withdraw");

        bunnyChef.notifyWithdrawn(msg.sender, share);

        _burn(msg.sender, share);
        _principals[msg.sender] = balanceOf(msg.sender).mul(totalLiquidity()).div(totalSupply());
        IStrategyVBNB(strategyVBNB).withdraw(msg.sender, bnbAmount);
    }

    function withdrawAll() external {
        uint share = balanceOf(msg.sender);
        if (share > 0) {
            withdraw(share);
        }
        getReward();
    }

    function getReward() public nonReentrant {
        bunnyChef.safeBunnyTransfer(msg.sender);
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

    function setBunnyChef(IBunnyChef _chef) public onlyOwner {
        require(address(bunnyChef) == address(0), "BankBNB: setBunnyChef only once");
        bunnyChef = IBunnyChef(_chef);
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

        uint balance = address(this).balance;
        if (balance > 0) {
            IStrategyVBNB(strategyVBNB).deposit{value : balance}();
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

    function recoverToken(address token, address to, uint value) external onlyOwner {
        token.safeTransfer(to, value);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _unifiedDebtShareKey() private view returns (address) {
        return address(this);
    }
}
