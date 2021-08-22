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

import "../library/WhitelistUpgradeable.sol";
import "../library/SafeToken.sol";

import "../interfaces/IBunnyPool.sol";
import "../interfaces/ISafeSwapBNB.sol";
import "../interfaces/IZap.sol";


contract BunnyFeeBox is WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT ========== */

    ISafeSwapBNB public constant safeSwapBNB = ISafeSwapBNB(0x8D36CB4C0aEa63ca095d9E26aeFb360D279176B0);
    IZap public constant zapBSC = IZap(0xdC2bBB0D33E0e7Dea9F5b98F46EDBaC823586a0C);

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant VAI = 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7;
    address private constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address private constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    address private constant DOT = 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402;
    address private constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address private constant DAI = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3;

    address private constant BUNNY_BNB = 0x5aFEf8567414F29f0f927A0F2787b188624c10E2;
    address private constant CAKE_BNB = 0x0eD7e52944161450477ee417DE9Cd3a859b14fD0;
    address private constant USDT_BNB = 0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE;
    address private constant BUSD_BNB = 0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16;
    address private constant USDT_BUSD = 0x7EFaEf62fDdCCa950418312c6C91Aef321375A00;
    address private constant VAI_BUSD = 0x133ee93FE93320e1182923E1a640912eDE17C90C;
    address private constant ETH_BNB = 0x74E4716E431f45807DCF19f284c7aA99F18a4fbc;
    address private constant BTCB_BNB = 0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082;
    address private constant DOT_BNB = 0xDd5bAd8f8b360d76d12FdA230F8BAF42fe0022CF;
    address private constant BTCB_BUSD = 0xF45cd219aEF8618A92BAa7aD848364a158a24F33;
    address private constant DAI_BUSD = 0x66FDB2eCCfB58cF098eaa419e5EfDe841368e489;
    address private constant USDC_BUSD = 0x2354ef4DF11afacb85a5C7f98B624072ECcddbB1;


    /* ========== STATE VARIABLES ========== */

    address public keeper;
    address public bunnyPool;

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), "BunnyFeeBox: caller is not the owner or keeper");
        _;
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __WhitelistUpgradeable_init();
    }

    /* ========== VIEWS ========== */

    function redundantTokens() public pure returns (address[8] memory) {
        return [USDT, BUSD, VAI, ETH, BTCB, USDC, DAI, DOT];
    }

    function flips() public pure returns (address[12] memory) {
        return [BUNNY_BNB, CAKE_BNB, USDT_BNB, BUSD_BNB, USDT_BUSD, VAI_BUSD, ETH_BNB, BTCB_BNB, DOT_BNB, BTCB_BUSD, DAI_BUSD, USDC_BUSD];
    }

    function pendingRewards() public view returns (uint bnb, uint cake, uint bunny) {
        bnb = address(this).balance;
        cake = IBEP20(CAKE).balanceOf(address(this));
        bunny = IBEP20(BUNNY).balanceOf(address(this));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }

    function setBunnyPool(address _bunnyPool) external onlyOwner {
        bunnyPool = _bunnyPool;
    }

    function swapToRewards() public onlyKeeper {
        require(bunnyPool != address(0), "BunnyFeeBox: BunnyPool must be set");

        address[] memory _tokens = IBunnyPool(bunnyPool).rewardTokens();
        uint[] memory _amounts = new uint[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            uint _amount = _tokens[i] == WBNB ? address(this).balance : IBEP20(_tokens[i]).balanceOf(address(this));
            if (_amount > 0) {
                if (_tokens[i] == WBNB) {
                    SafeToken.safeTransferETH(bunnyPool, _amount);
                } else {
                    IBEP20(_tokens[i]).safeTransfer(bunnyPool, _amount);
                }
            }
            _amounts[i] = _amount;
        }

        IBunnyPool(bunnyPool).notifyRewardAmounts(_amounts);
    }

    function harvest() external onlyKeeper {
        splitPairs();

        address[8] memory _tokens = redundantTokens();
        for (uint i = 0; i < _tokens.length; i++) {
            _convertToken(_tokens[i], IBEP20(_tokens[i]).balanceOf(address(this)));
        }

        swapToRewards();
    }

    function splitPairs() public onlyKeeper {
        address[12] memory _flips = flips();
        for (uint i = 0; i < _flips.length; i++) {
            _convertToken(_flips[i], IBEP20(_flips[i]).balanceOf(address(this)));
        }
    }

    function covertTokensPartial(address[] memory _tokens, uint[] memory _amounts) external onlyKeeper {
        for (uint i = 0; i < _tokens.length; i++) {
            _convertToken(_tokens[i], _amounts[i]);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _convertToken(address token, uint amount) private {
        uint balance = IBEP20(token).balanceOf(address(this));
        if (amount > 0 && balance >= amount) {
            if (IBEP20(token).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(token).approve(address(zapBSC), uint(- 1));
            }
            zapBSC.zapOut(token, amount);
        }
    }

    // @dev use when WBNB received from minter
    function _unwrap(uint amount) private {
        uint balance = IBEP20(WBNB).balanceOf(address(this));
        if (amount > 0 && balance >= amount) {
            if (IBEP20(WBNB).allowance(address(this), address(safeSwapBNB)) == 0) {
                IBEP20(WBNB).approve(address(safeSwapBNB), uint(-1));
            }

            safeSwapBNB.withdraw(amount);
        }
    }

}