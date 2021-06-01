// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";

library SortitionSumTreeFactory {

    struct SortitionSumTree {
        uint K;
        uint[] stack;
        uint[] nodes;
        mapping(bytes32 => uint) IDsToNodeIndexes;
        mapping(uint => bytes32) nodeIndexesToIDs;
    }

    /* ========== STATE VARIABLES ========== */

    struct SortitionSumTrees {
        mapping(bytes32 => SortitionSumTree) sortitionSumTrees;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function createTree(SortitionSumTrees storage self, bytes32 _key, uint _K) public {
        SortitionSumTree storage tree = self.sortitionSumTrees[_key];
        require(_K > 1, "K must be greater than one.");
        tree.K = _K;
        tree.stack = new uint[](0);
        tree.nodes = new uint[](0);
        tree.nodes.push(0);
    }

    function set(SortitionSumTrees storage self, bytes32 _key, uint _value, bytes32 _ID) public {
        SortitionSumTree storage tree = self.sortitionSumTrees[_key];
        uint treeIndex = Math.min(tree.IDsToNodeIndexes[_ID], tree.nodes.length - 1);

        if (treeIndex == 0) {
            if (_value != 0) {
                if (tree.stack.length == 0) {
                    treeIndex = tree.nodes.length;
                    tree.nodes.push(_value);

                    if (treeIndex != 1 && (treeIndex - 1) % tree.K == 0) {
                        uint parentIndex = treeIndex / tree.K;
                        bytes32 parentID = tree.nodeIndexesToIDs[parentIndex];
                        uint newIndex = treeIndex + 1;
                        tree.nodes.push(tree.nodes[parentIndex]);
                        delete tree.nodeIndexesToIDs[parentIndex];
                        tree.IDsToNodeIndexes[parentID] = newIndex;
                        tree.nodeIndexesToIDs[newIndex] = parentID;
                    }
                } else {
                    treeIndex = tree.stack[tree.stack.length - 1];
                    tree.stack.pop();
                    tree.nodes[treeIndex] = _value;
                }

                tree.IDsToNodeIndexes[_ID] = treeIndex;
                tree.nodeIndexesToIDs[treeIndex] = _ID;

                updateParents(self, _key, treeIndex, true, _value);
            }
        } else {
            if (_value == 0) {
                uint value = tree.nodes[treeIndex];
                tree.nodes[treeIndex] = 0;

                tree.stack.push(treeIndex);

                delete tree.IDsToNodeIndexes[_ID];
                delete tree.nodeIndexesToIDs[treeIndex];

                updateParents(self, _key, treeIndex, false, value);
            } else if (_value != tree.nodes[treeIndex]) {// New, non zero value.
                bool plusOrMinus = tree.nodes[treeIndex] <= _value;
                uint plusOrMinusValue = plusOrMinus ? _value - tree.nodes[treeIndex] : tree.nodes[treeIndex] - _value;
                tree.nodes[treeIndex] = _value;

                updateParents(self, _key, treeIndex, plusOrMinus, plusOrMinusValue);
            }
        }
    }

    function draw(SortitionSumTrees storage self, bytes32 _key, uint _drawnNumber) public returns (bytes32 ID) {
        SortitionSumTree storage tree = self.sortitionSumTrees[_key];
        uint treeIndex = 0;
        uint currentDrawnNumber = _drawnNumber % tree.nodes[0];

        while ((tree.K * treeIndex) + 1 < tree.nodes.length)
            for (uint i = 1; i <= tree.K; i++) {
                uint nodeIndex = (tree.K * treeIndex) + i;
                uint nodeValue = tree.nodes[nodeIndex];

                if (currentDrawnNumber >= nodeValue) currentDrawnNumber -= nodeValue;
                else {
                    treeIndex = nodeIndex;
                    break;
                }
            }

        ID = tree.nodeIndexesToIDs[treeIndex];
        tree.nodes[treeIndex] = 0;
    }

    function stakeOf(SortitionSumTrees storage self, bytes32 _key, bytes32 _ID) public view returns (uint value) {
        SortitionSumTree storage tree = self.sortitionSumTrees[_key];
        uint treeIndex = Math.min(tree.IDsToNodeIndexes[_ID], tree.nodes.length - 1);

        if (treeIndex == 0) value = 0;
        else value = tree.nodes[treeIndex];
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function updateParents(SortitionSumTrees storage self, bytes32 _key, uint _treeIndex, bool _plusOrMinus, uint _value) private {
        SortitionSumTree storage tree = self.sortitionSumTrees[_key];

        uint parentIndex = _treeIndex;
        while (parentIndex != 0) {
            parentIndex = (parentIndex - 1) / tree.K;
            tree.nodes[parentIndex] = _plusOrMinus ? tree.nodes[parentIndex] + _value : tree.nodes[parentIndex] - _value;
        }
    }
}
