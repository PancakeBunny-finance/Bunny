// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/WhitelistUpgradeable.sol";
import "../library/PausableUpgradeable.sol";
import "../library/SortitionSumTreeFactory.sol";

import "../interfaces/IPotController.sol";
import "../interfaces/IRNGenerator.sol";


contract PotController is IPotController, PausableUpgradeable, WhitelistUpgradeable {
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

    /* ========== CONSTANT ========== */

    uint constant private MAX_TREE_LEAVES = 5;
    IRNGenerator constant private RNGenerator = IRNGenerator(0x2Eb45a1017e9E0793E05aaF0796298d9b871eCad);

    /* ========== STATE VARIABLES ========== */

    SortitionSumTreeFactory.SortitionSumTrees private _sortitionSumTree;
    bytes32 private _requestId;  // random number

    uint internal _randomness;
    uint public potId;
    uint public startedAt;

    /* ========== MODIFIERS ========== */

    modifier onlyRandomGenerator() {
        require(msg.sender == address(RNGenerator), "Only random generator");
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function createTree(bytes32 key) internal {
        _sortitionSumTree.createTree(key, MAX_TREE_LEAVES);
    }

    function getWeight(bytes32 key, bytes32 _ID) internal view returns (uint) {
        return _sortitionSumTree.stakeOf(key, _ID);
    }

    function setWeight(bytes32 key, uint weight, bytes32 _ID) internal {
        _sortitionSumTree.set(key, weight, _ID);
    }

    function draw(bytes32 key, uint randomNumber) internal returns (address) {
        return address(uint(_sortitionSumTree.draw(key, randomNumber)));
    }

    function getRandomNumber(uint weight) internal {
        _requestId = RNGenerator.getRandomNumber(potId, weight);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    function numbersDrawn(uint _potId, bytes32 requestId, uint randomness) override external onlyRandomGenerator {
        if (_requestId == requestId && potId == _potId) {
            _randomness = randomness;
        }
    }
}
