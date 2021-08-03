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

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../../interfaces/IBank.sol";
import "../../interfaces/IPriceCalculator.sol";
import "../../library/WhitelistUpgradeable.sol";
import "../../library/SafeToken.sol";
import "../../library/PoolConstant.sol";

import "../../zap/ZapBSC.sol";
import "./VaultRelayInternal.sol";


contract VaultRelayer is WhitelistUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,address verifyingContract)");
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256("Deposit(address pool,uint256 bnbAmount,uint256 nonce,uint256 expiry)");
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("Withdraw(address pool,uint256 nonce,uint256 expiry)");

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address private constant BRIDGE = 0xE46Fbb655867CB122A3b14e03FC612Efb1AB6B7d;

    IBank private constant bank = IBank(0x926940FA307562Ac71Bb401525E1bBA6e32DBbb8);
    ZapBSC private constant zapBSC = ZapBSC(0xdC2bBB0D33E0e7Dea9F5b98F46EDBaC823586a0C);
    IPriceCalculator private constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint) public nonces;
    mapping(address => bool) private _testers;

    // pool -> account -> withdrawn history
    mapping(address => mapping(address => PoolConstant.RelayWithdrawn)) public withdrawnHistories;
    mapping(address => mapping(address => bool)) public withdrawing;

    /* ========== EVENTS ========== */

    event Deposited(address indexed pool, address indexed account, uint amount);
    event Withdrawn(address indexed pool, address indexed account, uint profitInETH, uint lossInETH);
    event Recovered(address token, uint amount);

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __WhitelistUpgradeable_init();

        if (IBEP20(CAKE).allowance(address(this), address(zapBSC)) == 0) {
            IBEP20(CAKE).safeApprove(address(zapBSC), uint(- 1));
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalSupply(address pool) external view returns (uint) {
        return VaultRelayInternal(pool).totalSupply();
    }

    function balanceOf(address pool, address account) external view returns (uint) {
        return VaultRelayInternal(pool).balanceOf(account);
    }

    function earnedOf(address pool, address account) public view returns (uint) {
        return VaultRelayInternal(pool).earned(account);
    }

    function balanceInUSD(address pool, address account) public view returns (uint) {
        VaultRelayInternal vault = VaultRelayInternal(pool);
        uint flipBalance = vault.balanceOf(account);
        (, uint flipInUSD) = priceCalculator.valueOfAsset(vault.stakingToken(), flipBalance);
        return flipInUSD;
    }

    function earnedInUSD(address pool, address account) public view returns (uint) {
        VaultRelayInternal vault = VaultRelayInternal(pool);
        uint cakeBalance = vault.earned(account);
        (, uint cakeInUSD) = priceCalculator.valueOfAsset(CAKE, cakeBalance);
        return cakeInUSD;
    }

    function debtInUSD(address pool, address account) public view returns (uint) {
        (, uint valueInUSD) = priceCalculator.valueOfAsset(WBNB, bank.pendingDebtOf(pool, account));
        return valueInUSD;
    }

    function isTester(address account) public view returns (bool) {
        return _testers[account];
    }

    function withdrawnHistoryOf(address pool, address account) public view returns (PoolConstant.RelayWithdrawn memory) {
        return withdrawnHistories[pool][account];
    }

    /**
      * @return nonce The nonce per account
      * @return debt The borrowed value of account in USD
      * @return value The borrowing value of account in USD
      * @return utilizable The Liquidity remain of BankBNB
      */
    function validateDeposit(address pool, address account, uint bnbAmount) public view returns (uint nonce, uint debt, uint value, uint utilizable) {
        (uint liquidity, uint utilized) = bank.getUtilizationInfo();
        (, uint valueInUSD) = priceCalculator.valueOfAsset(WBNB, bnbAmount);
        return (nonces[account], debtInUSD(pool, account), valueInUSD, liquidity.sub(utilized));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    /**
     * @param pool BSC Pool address
     * @param bnbAmount BNB amount to borrow
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function depositBySig(address pool, uint bnbAmount, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) external onlyWhitelisted {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("VaultRelayer")), address(this)));
        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, pool, bnbAmount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        require(signatory != address(0), "VaultRelayer: invalid signature");
        require(isTester(signatory), "VaultRelayer: not tester");
        require(nonce == nonces[signatory]++, "VaultRelayer: invalid nonce");
        require(now <= expiry, "VaultRelayer: signature expired");
        _deposit(pool, signatory, bnbAmount);
    }

    function withdrawBySig(address pool, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) external onlyWhitelisted {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("VaultRelayer")), address(this)));
        bytes32 structHash = keccak256(abi.encode(WITHDRAW_TYPEHASH, pool, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        require(signatory != address(0), "VaultRelayer: invalid signature");
        require(nonce == nonces[signatory]++, "VaultRelayer: invalid nonce");
        require(now <= expiry, "VaultRelayer: signature expired");
        _withdraw(pool, signatory);
    }

    function completeWithdraw(address pool, address account) external onlyWhitelisted {
        delete withdrawing[pool][account];
        delete withdrawnHistories[pool][account];
    }

    function liquidate(address pool, address account) external onlyWhitelisted {
        _withdraw(pool, account);
    }

    function setTester(address account, bool on) external onlyOwner {
        _testers[account] = on;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _deposit(address pool, address account, uint bnbAmount) private {
        (uint liquidity, uint utilized) = bank.getUtilizationInfo();
        bnbAmount = Math.min(bnbAmount, liquidity.sub(utilized));
        require(bnbAmount > 0, "VaultRelayer: not enough amount");
        require(!withdrawing[pool][account], "VaultRelayer: withdrawing must be complete");

        VaultRelayInternal vault = VaultRelayInternal(pool);
        address flip = vault.stakingToken();

        uint _beforeBNB = address(this).balance;
        bank.borrow(pool, account, bnbAmount);
        bnbAmount = address(this).balance.sub(_beforeBNB);

        uint _beforeFlip = IBEP20(flip).balanceOf(address(this));
        zapBSC.zapIn{value : bnbAmount}(flip);
        uint flipAmount = IBEP20(flip).balanceOf(address(this)).sub(_beforeFlip);

        if (IBEP20(flip).allowance(address(this), pool) == 0) {
            IBEP20(flip).safeApprove(pool, uint(- 1));
        }

        vault.deposit(flipAmount, account);
        delete withdrawnHistories[pool][account];
        emit Deposited(pool, account, flipAmount);
    }

    function _withdraw(address pool, address account) private {
        require(!withdrawing[pool][account], "VaultRelayer: withdrawing must be complete");
        if (VaultRelayInternal(pool).balanceOf(account) == 0) return;
        withdrawing[pool][account] = true;

        (uint flipAmount, uint cakeAmount) = _withdrawInternal(pool, account);
        uint bnbAmount = _zapOutToBNB(pool, flipAmount, cakeAmount);
        (uint profitInETH, uint lossInETH) = bank.repayAll{value : bnbAmount}(pool, account);

        PoolConstant.RelayWithdrawn storage history = withdrawnHistories[pool][account];
        history.pool = pool;
        history.account = account;
        history.profitInETH = history.profitInETH.add(profitInETH);
        history.lossInETH = history.lossInETH.add(lossInETH);

        if (profitInETH > lossInETH) {
            bank.bridgeETH(BRIDGE, profitInETH.sub(lossInETH));
        }
        emit Withdrawn(pool, account, profitInETH, lossInETH);
    }

    function _withdrawInternal(address pool, address account) private returns (uint flipAmount, uint cakeAmount) {
        VaultRelayInternal vault = VaultRelayInternal(pool);
        address flip = vault.stakingToken();

        uint _beforeFlip = IBEP20(flip).balanceOf(address(this));
        uint _beforeCake = IBEP20(CAKE).balanceOf(address(this));

        vault.withdrawAll(account);
        flipAmount = IBEP20(flip).balanceOf(address(this)).sub(_beforeFlip);
        cakeAmount = IBEP20(CAKE).balanceOf(address(this)).sub(_beforeCake);
    }

    function _zapOutToBNB(address pool, uint flipAmount, uint cakeAmount) private returns (uint) {
        uint _beforeBNB = address(this).balance;

        address flip = VaultRelayInternal(pool).stakingToken();
        IPancakePair pair = IPancakePair(flip);
        address pairToken = pair.token0() == WBNB ? pair.token1() : pair.token0();

        uint _beforePairTokenAmount = IBEP20(pairToken).balanceOf(address(this));

        _approveIfNeeded(flip);
        if (flipAmount > 0) zapBSC.zapOut(flip, flipAmount);
        if (cakeAmount > 0) zapBSC.zapOut(CAKE, cakeAmount);

        uint pairTokenAmount = IBEP20(pairToken).balanceOf(address(this)).sub(_beforePairTokenAmount);
        if (pairTokenAmount > 0) {
            _approveIfNeeded(pairToken);
            zapBSC.zapOut(pairToken, pairTokenAmount);
        }
        return address(this).balance.sub(_beforeBNB);
    }

    function _approveIfNeeded(address token) private {
        if (IBEP20(token).allowance(address(this), address(zapBSC)) == 0) {
            IBEP20(token).safeApprove(address(zapBSC), uint(- 1));
        }
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external onlyOwner {
        require(
            tokenAddress != address(0) &&
            tokenAddress != CAKE &&
            keccak256(abi.encodePacked(IPancakePair(tokenAddress).symbol())) == keccak256("Cake-LP"),
            "VaultRelayer: cannot recover token");

        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
