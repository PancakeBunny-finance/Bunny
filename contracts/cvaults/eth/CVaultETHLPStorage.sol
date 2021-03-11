// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./CVaultETHLPState.sol";
import "../../library/PausableUpgradeable.sol";
import "../interface/ICVaultRelayer.sol";


contract CVaultETHLPStorage is CVaultETHLPState, PausableUpgradeable {
    using SafeMath for uint;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint public constant EMERGENCY_EXIT_TIMELOCK = 72 hours;
    uint public constant COLLATERAL_RATIO_MIN = 18e17;  // 180%

    uint128 public constant LEVERAGE_MAX = 15e17;       // 150%
    uint128 public constant LEVERAGE_MIN = 1e17;        // 10%

    uint public constant LIQUIDATION_PENALTY = 5e16;    // 5%
    uint public constant LIQUIDATION_FEE = 30e16;       // 30%  *** 30% of 5% penalty goes to treasury
    uint public constant UNIT = 1e18;                   // 100%

    uint public constant WITHDRAWAL_FEE_PERIOD = 3 days;
    uint public constant WITHDRAWAL_FEE = 5e15;         // 0.5%

    ICVaultRelayer public relayer;
    mapping(address => Pool) private _pools;
    mapping(address => uint) private _unpaidETH;

    uint public totalUnpaidETH;

    uint[50] private _gap;

    modifier increaseNonceOnlyRelayers(address lp, address _account, uint112 nonce) {
        require(msg.sender == address(relayer), "CVaultETHLPStorage: not a relayer");
        require(accountOf(lp, _account).nonce == nonce, "CVaultETHLPStorage: invalid nonce");
        _;
        increaseNonce(lp, _account);
    }

    modifier onlyStateFarming(address lp) {
        require(stateOf(lp, msg.sender) == State.Farming, "CVaultETHLPStorage: not farming state");
        _;
    }

    modifier validLeverage(uint128 leverage) {
        require(LEVERAGE_MIN <= leverage && leverage <= LEVERAGE_MAX, "CVaultETHLPStorage: leverage range should be [10%-150%]");
        _;
    }

    modifier notPausedPool(address lp) {
        require(_pools[lp].paused == false, "CVaultETHLPStorage: paused pool");
        _;
    }

    receive() external payable {}

    // ---------- INITIALIZER ----------

    function __CVaultETHLPStorage_init() internal initializer {
        __PausableUpgradeable_init();
    }

    // ---------- RESTRICTED ----------

    function _setPool(address lp, address bscFlip) internal onlyOwner {
        require(_pools[lp].bscFlip == address(0), "CVaultETHLPStorage: setPool already");
        _pools[lp].bscFlip = bscFlip;
    }

    function pausePool(address lp, bool paused) external onlyOwner {
        _pools[lp].paused = paused;
    }

    function setCVaultRelayer(address newRelayer) external onlyOwner {
        relayer = ICVaultRelayer(newRelayer);
    }

    // ---------- VIEW ----------

    function bscFlipOf(address lp) public view returns (address) {
        return _pools[lp].bscFlip;
    }

    function totalCollateralOf(address lp) public view returns (uint) {
        return _pools[lp].totalCollateral;
    }

    function stateOf(address lp, address account) public view returns (State) {
        return _pools[lp].accounts[account].state;
    }

    function accountOf(address lp, address account) public view returns (Account memory) {
        return _pools[lp].accounts[account];
    }

    function unpaidETH(address account) public view returns (uint) {
        return _unpaidETH[account];
    }

    function withdrawalFee(address lp, address account, uint amount) public view returns (uint) {
        if (_pools[lp].accounts[account].depositedAt + WITHDRAWAL_FEE_PERIOD < block.timestamp) {
            return 0;
        }

        return amount.mul(WITHDRAWAL_FEE).div(UNIT);
    }

    // ---------- SET ----------
    function increaseUnpaidETHValue(address _account, uint value) internal {
        _unpaidETH[_account] = _unpaidETH[_account].add(value);
        totalUnpaidETH = totalUnpaidETH.add(value);
    }

    function decreaseUnpaidETHValue(address _account, uint value) internal {
        _unpaidETH[_account] = _unpaidETH[_account].sub(value);
        totalUnpaidETH = totalUnpaidETH.sub(value);
    }

    function increaseCollateral(address lp, address _account, uint amount) internal returns (uint collateral) {
        Account storage account = _pools[lp].accounts[_account];
        collateral = account.collateral.add(amount);
        account.collateral = collateral;

        _pools[lp].totalCollateral = _pools[lp].totalCollateral.add(amount);
    }

    function decreaseCollateral(address lp, address _account, uint amount) internal returns (uint collateral) {
        Account storage account = _pools[lp].accounts[_account];
        collateral = account.collateral.sub(amount);
        account.collateral = collateral;

        _pools[lp].totalCollateral = _pools[lp].totalCollateral.sub(amount);
    }

    function setLeverage(address lp, address _account, uint128 leverage) internal {
        _pools[lp].accounts[_account].leverage = leverage;
    }

    function setWithdrawalRequestAmount(address lp, address _account, uint amount) internal {
        _pools[lp].accounts[_account].withdrawalRequestAmount = amount;
    }

    function setBSCBNBDebt(address lp, address _account, uint bscBNBDebt) internal {
        _pools[lp].accounts[_account].bscBNBDebt = bscBNBDebt;
    }

    function setBSCFlipBalance(address lp, address _account, uint bscFlipBalance) internal {
        _pools[lp].accounts[_account].bscFlipBalance = bscFlipBalance;
    }

    function increaseNonce(address lp, address _account) private {
        _pools[lp].accounts[_account].nonce++;
    }

    function setUpdatedAt(address lp, address _account) private {
        _pools[lp].accounts[_account].updatedAt = uint64(block.timestamp);
    }

    function setDepositedAt(address lp, address _account) private {
        _pools[lp].accounts[_account].depositedAt = uint64(block.timestamp);
    }

    function setLiquidator(address lp, address _account, address liquidator) internal {
        _pools[lp].accounts[_account].liquidator = liquidator;
    }

    function setState(address lp, address _account, State state) private {
        _pools[lp].accounts[_account].state = state;
    }

    function resetAccountExceptNonceAndState(address lp, address _account) private {
        Account memory account = _pools[lp].accounts[_account];
        _pools[lp].accounts[_account] = Account(0, 0, 0, 0, account.nonce, 0, 0, address(0), account.state, 0);
    }

    function convertState(address lp, address _account, State state) internal {
        Account memory account = _pools[lp].accounts[_account];
        State currentState = account.state;
        if (state == State.Idle) {
            require(msg.sender == address(relayer), "CVaultETHLPStorage: only relayer can resolve emergency state");
            require(currentState == State.Withdrawing || currentState == State.Liquidating || currentState == State.EmergencyExited,
                "CVaultETHLPStorage: can't convert to Idle"
            );
            resetAccountExceptNonceAndState(lp, _account);
        } else if (state == State.Depositing) {
            require(currentState == State.Idle || currentState == State.Farming,
                "CVaultETHLPStorage: can't convert to Depositing");
            setDepositedAt(lp, _account);
        } else if (state == State.Farming) {
            require(currentState == State.Depositing || currentState == State.UpdatingLeverage,
                "CVaultETHLPStorage: can't convert to Farming");
        } else if (state == State.Withdrawing) {
            require(currentState == State.Farming,
                "CVaultETHLPStorage: can't convert to Withdrawing");
        } else if (state == State.UpdatingLeverage) {
            require(currentState == State.Farming,
                "CVaultETHLPStorage: can't convert to UpdatingLeverage");
        } else if (state == State.Liquidating) {
            require(currentState == State.Farming,
                "CVaultETHLPStorage: can't convert to Liquidating"
            );
        } else if (state == State.EmergencyExited) {
            require(_account == msg.sender, "CVaultETHLPStorage: msg.sender is not the owner of account");
            require(currentState == State.Depositing || currentState == State.Withdrawing || currentState == State.UpdatingLeverage, "CVaultETHLPStorage: unavailable state to emergency exit");
            require(account.updatedAt + EMERGENCY_EXIT_TIMELOCK < block.timestamp, "CVaultETHLPStorage: timelocked");
        } else {
            revert("Invalid state");
        }

        setState(lp, _account, state);
        setUpdatedAt(lp, _account);
    }
}
