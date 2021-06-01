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
import "../../library/WhitelistUpgradeable.sol";

import "../../interfaces/IPriceCalculator.sol";
import "../../zap/ZapBSC.sol";
import "./VaultCompensation.sol";


contract CompensationTreasury is WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    address public constant keeper = 0xF49AD469e4A12921d0373C1EFDE108469Bac652f;

    IPriceCalculator public constant priceCalculator = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);
    ZapBSC public constant zapBSC = ZapBSC(0xdC2bBB0D33E0e7Dea9F5b98F46EDBaC823586a0C);

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BUNNY = 0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public constant VAI = 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7;
    address public constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address public constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;

    address public constant BUNNY_BNB = 0x5aFEf8567414F29f0f927A0F2787b188624c10E2;
    address public constant CAKE_BNB = 0x0eD7e52944161450477ee417DE9Cd3a859b14fD0;
    address public constant USDT_BNB = 0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE;
    address public constant BUSD_BNB = 0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16;
    address public constant USDT_BUSD = 0x7EFaEf62fDdCCa950418312c6C91Aef321375A00;
    address public constant VAI_BUSD = 0x133ee93FE93320e1182923E1a640912eDE17C90C;
    address public constant ETH_BNB = 0x74E4716E431f45807DCF19f284c7aA99F18a4fbc;
    address public constant BTCB_BNB = 0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082;

    /* ========== STATE VARIABLES ========== */

    VaultCompensation public vaultCompensation;

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), 'CompTreasury: caller is not the owner or keeper');
        _;
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== VIEW FUNCTIONS ========== */

    function redundantTokens() public pure returns (address[5] memory) {
        return [USDT, BUSD, VAI, ETH, BTCB];
    }

    function flips() public pure returns (address[8] memory) {
        return [BUNNY_BNB, CAKE_BNB, USDT_BNB, BUSD_BNB, USDT_BUSD, VAI_BUSD, ETH_BNB, BTCB_BNB];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setVaultCompensation(address payable _vaultCompensation) public onlyKeeper {
        vaultCompensation = VaultCompensation(_vaultCompensation);
    }

    function compensate() public onlyKeeper {
        require(address(vaultCompensation) != address(0), "CompTreasury: vault compensation must be set");
        _convertTokens();

        address[] memory _tokens = vaultCompensation.rewardTokens();
        uint[] memory _amounts = new uint[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            uint _amount = _tokens[i] == WBNB ? address(this).balance : IBEP20(_tokens[i]).balanceOf(address(this));
            if (_amount > 0) {
                if (_tokens[i] == WBNB) {
                    SafeToken.safeTransferETH(address(vaultCompensation), _amount);
                } else {
                    IBEP20(_tokens[i]).safeTransfer(address(vaultCompensation), _amount);
                }
            }
            _amounts[i] = _amount;
        }
        vaultCompensation.notifyRewardAmounts(_amounts);
    }

    function buyback() public onlyKeeper {
        uint balance = Math.min(IBEP20(CAKE).balanceOf(address(this)), 2000e18);
        if (balance > 0) {
            if (IBEP20(CAKE).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(CAKE).approve(address(zapBSC), uint(- 1));
            }
            zapBSC.zapInToken(CAKE, balance, BUNNY);
        }
    }

    function splitPairs() public onlyKeeper {
        address[8] memory _flips = flips();
        for (uint i = 0; i < _flips.length; i++) {
            address flip = _flips[i];
            uint balance = IBEP20(flip).balanceOf(address(this));
            if (balance > 0) {
                if (IBEP20(flip).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(flip).approve(address(zapBSC), uint(- 1));
                }
                zapBSC.zapOut(_flips[i], IBEP20(_flips[i]).balanceOf(address(this)));
            }
        }
    }

    function covertTokensPartial(address[] memory _tokens, uint[] memory _amounts) public onlyKeeper {
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint balance = IBEP20(token).balanceOf(address(this));
            if (balance >= _amounts[i]) {
                if (IBEP20(token).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token).approve(address(zapBSC), uint(- 1));
                }
                zapBSC.zapOut(_tokens[i], _amounts[i]);
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _convertTokens() private {
        splitPairs();

        address[5] memory _tokens = redundantTokens();
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint balance = IBEP20(token).balanceOf(address(this));
            if (balance > 0) {
                if (IBEP20(token).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token).approve(address(zapBSC), uint(- 1));
                }
                zapBSC.zapOut(_tokens[i], balance);
            }
        }
    }
}
