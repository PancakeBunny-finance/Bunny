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

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interface/ICVaultRelayer.sol";
import "./interface/ICVaultETHLP.sol";
import "./interface/ICVaultBSCFlip.sol";


contract CVaultRelayer is ICVaultRelayer, OwnableUpgradeable {
    using SafeMath for uint;

    uint8 public constant SIG_DEPOSIT = 10;
    uint8 public constant SIG_LEVERAGE = 20;
    uint8 public constant SIG_WITHDRAW = 30;
    uint8 public constant SIG_LIQUIDATE = 40;
    uint8 public constant SIG_EMERGENCY = 50;
    uint8 public constant SIG_CLEAR = 63;

    address public constant BNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /* ========== STATE VARIABLES ========== */

    address public cvaultETH;
    address public cvaultBSC;

    uint public bankLiquidity;
    uint public bankUtilized;

    uint128 public pendingId;
    uint128 public completeId;
    uint128 public liqPendingId;
    uint128 public liqCompleteId;

    mapping(uint128 => RelayRequest) public requests;
    mapping(uint128 => RelayResponse) public responses;
    mapping(uint128 => RelayLiquidation) public liquidations;

    mapping(address => bool) private _relayHandlers;
    mapping(address => uint) private _tokenPrices;

    /* ========== EVENTS ========== */

    event RelayCompleted(uint128 indexed completeId, uint128 count);
    event RelayFailed(uint128 indexed requestId);

    /* ========== MODIFIERS ========== */

    modifier onlyCVaultETH() {
        require(cvaultETH != address(0) && msg.sender == cvaultETH, "CVaultRelayer: call is not the cvault eth");
        _;
    }

    modifier onlyRelayHandlers() {
        require(_relayHandlers[msg.sender], "CVaultRelayer: caller is not the relay handler");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
        require(owner() != address(0), "CVaultRelayer: owner must be set");
    }

    /* ========== RELAY VIEW FUNCTIONS ========== */

    function getPendingRequestsOnETH(uint128 limit) public view returns (RelayRequest[] memory) {
        if (pendingId < completeId) {
            return new RelayRequest[](0);
        }

        uint128 count = pendingId - completeId;
        count = count > limit ? limit : count;
        RelayRequest[] memory pendingRequests = new RelayRequest[](count);

        ICVaultETHLP cvaultETHLP = ICVaultETHLP(cvaultETH);
        for (uint128 index = 0; index < count; index++) {
            uint128 requestId = completeId + index + uint128(1);
            RelayRequest memory request = requests[requestId];

            (uint8 validation, uint112 nonce) = cvaultETHLP.validateRequest(request.signature, request.lp, request.account, request.leverage, request.collateral);
            request.validation = validation;
            request.nonce = nonce;

            pendingRequests[index] = request;
        }
        return pendingRequests;
    }

    function getPendingResponsesOnBSC(uint128 limit) public view returns (RelayResponse[] memory) {
        if (pendingId < completeId) {
            return new RelayResponse[](0);
        }

        uint128 count = pendingId - completeId;
        count = count > limit ? limit : count;
        RelayResponse[] memory pendingResponses = new RelayResponse[](count);

        uint128 returnCounter = count;
        for (uint128 requestId = pendingId; requestId > pendingId - count; requestId--) {
            returnCounter--;
            pendingResponses[returnCounter] = responses[requestId];
        }
        return pendingResponses;
    }

    function getPendingLiquidationCountOnETH() public view returns (uint) {
        if (liqPendingId < liqCompleteId) {
            return 0;
        }
        return liqPendingId - liqCompleteId;
    }

    function canAskLiquidation(address lp, address account) public view returns (bool) {
        if (liqPendingId < liqCompleteId) {
            return true;
        }

        uint128 count = liqPendingId - liqCompleteId;
        for (uint128 liqId = liqPendingId; liqId > liqPendingId - count; liqId--) {
            RelayLiquidation memory each = liquidations[liqId];
            if (each.lp == lp && each.account == account) {
                return false;
            }
        }
        return true;
    }

    function getHistoriesOf(uint128[] calldata selector) public view returns (RelayHistory[] memory) {
        RelayHistory[] memory histories = new RelayHistory[](selector.length);

        for (uint128 index = 0; index < selector.length; index++) {
            uint128 requestId = selector[index];
            histories[index] = RelayHistory({requestId : requestId, request : requests[requestId], response : responses[requestId]});
        }
        return histories;
    }

    /* ========== ORACLE VIEW FUNCTIONS ========== */

    function valueOfAsset(address token, uint amount) public override view returns (uint) {
        return priceOf(token).mul(amount).div(1e18);
    }

    function priceOf(address token) public override view returns (uint) {
        return _tokenPrices[token];
    }

    function collateralRatioOnETH(address lp, uint lpAmount, address flip, uint flipAmount, uint debt) external override view returns (uint) {
        uint lpValue = valueOfAsset(lp, lpAmount);
        uint flipValue = valueOfAsset(flip, flipAmount);
        uint debtValue = valueOfAsset(BNB, debt);

        if (debtValue == 0) {
            return uint(- 1);
        }
        return lpValue.add(flipValue).mul(1e18).div(debtValue);
    }

    function utilizationInfo() public override view returns (uint liquidity, uint utilized) {
        return (bankLiquidity, bankUtilized);
    }

    function utilizationInfoOnBSC() public view returns (uint liquidity, uint utilized) {
        return ICVaultBSCFlip(cvaultBSC).getUtilizationInfo();
    }

    function isUtilizable(address lp, uint amount, uint leverage) external override view returns (bool) {
        if (bankUtilized >= bankLiquidity) return false;

        uint availableBNBSupply = bankLiquidity.sub(bankUtilized);
        return valueOfAsset(BNB, availableBNBSupply) >= valueOfAsset(lp, amount).mul(leverage).div(1e18);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setCVaultETH(address _cvault) external onlyOwner {
        cvaultETH = _cvault;
    }

    function setCVaultBSC(address _cvault) external onlyOwner {
        cvaultBSC = _cvault;
    }

    function setRelayHandler(address newRelayHandler, bool permission) external onlyOwner {
        _relayHandlers[newRelayHandler] = permission;
    }

    /* ========== RELAY FUNCTIONS ========== */
    /*
    * tx 1.   CVaultETH           requestRelayOnETH          -> CVaultRelayer enqueues request
    * tx 2-1. CVaultRelayHandlers getPendingRequestsOnETH    -> CVaultRelayer returns pending request list
    * tx 2-2. CVaultRelayHandlers transferRelaysOnBSC        -> CVaultRelayer handles request list by signature and update response list
    * tx 3-1. CVaultRelayHandlers getPendingResponsesOnBSC   -> CVaultRelayer returns pending response list
    * tx 3-2. CVaultRelayHandlers completeRelaysOnETH        -> CVaultRelayer handles response list by signature and update completeId
    * tx 3-3. CVaultRelayHandlers syncCompletedRelaysOnBSC   -> CVaultRelayer synchronize completeId
    */

    function requestRelayOnETH(address lp, address account, uint8 signature, uint128 leverage, uint collateral, uint lpAmount) public override onlyCVaultETH returns (uint requestId) {
        pendingId++;
        RelayRequest memory request = RelayRequest({
        lp : lp, account : account, signature : signature, validation : uint8(0), nonce : uint112(0), requestId : pendingId,
        leverage : leverage, collateral : collateral, lpValue : valueOfAsset(lp, lpAmount)
        });
        requests[pendingId] = request;
        return pendingId;
    }

    function transferRelaysOnBSC(RelayRequest[] memory _requests) external onlyRelayHandlers {
        require(cvaultBSC != address(0), "CVaultRelayer: cvaultBSC must be set");

        ICVaultBSCFlip cvaultBSCFlip = ICVaultBSCFlip(cvaultBSC);
        for (uint index = 0; index < _requests.length; index++) {
            RelayRequest memory request = _requests[index];
            RelayResponse memory response = RelayResponse({
            lp : request.lp, account : request.account,
            signature : request.signature, validation : request.validation, nonce : request.nonce, requestId : request.requestId,
            bscBNBDebtShare : 0, bscFlipBalance : 0, ethProfit : 0, ethLoss : 0
            });

            if (request.validation != uint8(0)) {
                if (request.signature == SIG_DEPOSIT) {
                    (uint bscBNBDebtShare, uint bscFlipBalance) = cvaultBSCFlip.deposit(request.lp, request.account, request.requestId, request.nonce, request.leverage, request.collateral);
                    response.bscBNBDebtShare = bscBNBDebtShare;
                    response.bscFlipBalance = bscFlipBalance;
                }
                else if (request.signature == SIG_LEVERAGE) {
                    (uint bscBNBDebtShare, uint bscFlipBalance) = cvaultBSCFlip.updateLeverage(request.lp, request.account, request.requestId, request.nonce, request.leverage, request.collateral);
                    response.bscBNBDebtShare = bscBNBDebtShare;
                    response.bscFlipBalance = bscFlipBalance;
                }
                else if (request.signature == SIG_WITHDRAW) {
                    (uint ethProfit, uint ethLoss) = cvaultBSCFlip.withdrawAll(request.lp, request.account, request.requestId, request.nonce);
                    response.ethProfit = ethProfit;
                    response.ethLoss = ethLoss;
                }
                else if (request.signature == SIG_EMERGENCY) {
                    (uint ethProfit, uint ethLoss) = cvaultBSCFlip.emergencyExit(request.lp, request.account, request.requestId, request.nonce);
                    response.ethProfit = ethProfit;
                    response.ethLoss = ethLoss;
                }
                else if (request.signature == SIG_LIQUIDATE) {
                    (uint ethProfit, uint ethLoss) = cvaultBSCFlip.liquidate(request.lp, request.account, request.requestId, request.nonce);
                    response.ethProfit = ethProfit;
                    response.ethLoss = ethLoss;
                }
                else if (request.signature == SIG_CLEAR) {
                    (uint ethProfit, uint ethLoss) = cvaultBSCFlip.withdrawAll(request.lp, request.account, request.requestId, request.nonce);
                    response.ethProfit = ethProfit;
                    response.ethLoss = ethLoss;
                }
            }

            requests[request.requestId] = request;
            responses[response.requestId] = response;
            pendingId++;
        }

        (bankLiquidity, bankUtilized) = cvaultBSCFlip.getUtilizationInfo();
    }

    function completeRelaysOnETH(RelayResponse[] memory _responses, RelayUtilization memory utilization) external onlyRelayHandlers {
        bankLiquidity = utilization.liquidity;
        bankUtilized = utilization.utilized;

        for (uint index = 0; index < _responses.length; index++) {
            RelayResponse memory response = _responses[index];
            bool success;
            if (response.validation != uint8(0)) {
                if (response.signature == SIG_DEPOSIT) {
                    (success,) = cvaultETH.call(
                        abi.encodeWithSignature("notifyDeposited(address,address,uint128,uint112,uint256,uint256)",
                        response.lp, response.account, response.requestId, response.nonce, response.bscBNBDebtShare, response.bscFlipBalance)
                    );
                } else if (response.signature == SIG_LEVERAGE) {
                    (success,) = cvaultETH.call(
                        abi.encodeWithSignature("notifyUpdatedLeverage(address,address,uint128,uint112,uint256,uint256)",
                        response.lp, response.account, response.requestId, response.nonce, response.bscBNBDebtShare, response.bscFlipBalance)
                    );
                } else if (response.signature == SIG_WITHDRAW) {
                    (success,) = cvaultETH.call(
                        abi.encodeWithSignature("notifyWithdrawnAll(address,address,uint128,uint112,uint256,uint256)",
                        response.lp, response.account, response.requestId, response.nonce, response.ethProfit, response.ethLoss)
                    );
                } else if (response.signature == SIG_EMERGENCY) {
                    (success,) = cvaultETH.call(
                        abi.encodeWithSignature("notifyResolvedEmergency(address,address,uint128,uint112)",
                        response.lp, response.account, response.requestId, response.nonce)
                    );
                } else if (response.signature == SIG_LIQUIDATE) {
                    (success,) = cvaultETH.call(
                        abi.encodeWithSignature("notifyLiquidated(address,address,uint128,uint112,uint256,uint256)",
                        response.lp, response.account, response.requestId, response.nonce, response.ethProfit, response.ethLoss)
                    );
                } else if (response.signature == SIG_CLEAR) {
                    success = true;
                }

                if (!success) {
                    emit RelayFailed(response.requestId);
                }
            }

            responses[response.requestId] = response;
            completeId++;
        }
        emit RelayCompleted(completeId, uint128(_responses.length));
    }

    function syncCompletedRelaysOnBSC(uint128 _count) external onlyRelayHandlers {
        completeId = completeId + _count;
        emit RelayCompleted(completeId, _count);
    }

    function syncUtilization(RelayUtilization memory utilization) external onlyRelayHandlers {
        bankLiquidity = utilization.liquidity;
        bankUtilized = utilization.utilized;
    }

    /* ========== LIQUIDATION FUNCTIONS ========== */

    function askLiquidationFromHandler(RelayLiquidation[] memory asks) external override onlyRelayHandlers {
        for (uint index = 0; index < asks.length; index++) {
            RelayLiquidation memory each = asks[index];
            if (canAskLiquidation(each.lp, each.account)) {
                liqPendingId++;
                liquidations[liqPendingId] = each;
            }
        }
    }

    function askLiquidationFromCVaultETH(address lp, address account, address liquidator) public override onlyCVaultETH {
        if (canAskLiquidation(lp, account)) {
            liqPendingId++;
            RelayLiquidation memory liquidation = RelayLiquidation({lp : lp, account : account, liquidator : liquidator});
            liquidations[liqPendingId] = liquidation;
        }
    }

    function executeLiquidationOnETH() external override onlyRelayHandlers {
        require(liqPendingId > liqCompleteId, "CVaultRelayer: no pending liquidations");

        ICVaultETHLP cvaultETHLP = ICVaultETHLP(cvaultETH);
        for (uint128 index = 0; index < liqPendingId - liqCompleteId; index++) {
            RelayLiquidation memory each = liquidations[liqCompleteId + index + uint128(1)];
            cvaultETHLP.executeLiquidation(each.lp, each.account, each.liquidator);
            liqCompleteId++;
        }
    }

    /* ========== ORACLE FUNCTIONS ========== */

    function setOraclePairData(RelayOracleData[] calldata data) external onlyRelayHandlers {
        for (uint index = 0; index < data.length; index++) {
            RelayOracleData calldata each = data[index];
            _tokenPrices[each.token] = each.price;
        }
    }
}
