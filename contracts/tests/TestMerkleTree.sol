// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {MerkleTreeLib} from "./TestMerkleTreeCalculateLib.sol";

library MerkleTreeCalculate {
    using MerkleTreeLib for uint256;
    using MerkleTreeLib for bytes32;
    using MerkleTreeLib for MerkleTreeLib.MergeValue;

    error InvalidMergeValue();

    function merge(
        uint8 height,
        bytes32 nodeKey,
        MerkleTreeLib.MergeValue memory lhs,
        MerkleTreeLib.MergeValue memory rhs,
        MerkleTreeLib.MergeValue memory v
    ) internal pure {
        if (lhs.mergeValue.value2.isZero() && rhs.mergeValue.value2.isZero()) {
            // return same value
        } else if (lhs.mergeValue.value2.isZero()) {
            mergeWithZero(height, nodeKey, rhs, v, true);
        } else if (rhs.mergeValue.value2.isZero()) {
            mergeWithZero(height, nodeKey, lhs, v, false);
        } else {
            bytes32 hashValueLeft;
            bytes32 hashValueRight;
            if (lhs.mergeType == MerkleTreeLib.MergeValueType.VALUE) {
                hashValueLeft = lhs.mergeValue.value2;
            } else {
                hashValueLeft = keccak256(
                    abi.encode(
                        MerkleTreeLib.MERGE_ZEROS,
                        lhs.mergeValue.value2, // baseNode
                        lhs.mergeValue.value3, // zeroBits
                        lhs.mergeValue.value1 // zeroCount
                    )
                );
            }
            if (rhs.mergeType == MerkleTreeLib.MergeValueType.VALUE) {
                hashValueRight = rhs.mergeValue.value2;
            } else {
                hashValueRight = keccak256(
                    abi.encode(
                        MerkleTreeLib.MERGE_ZEROS,
                        rhs.mergeValue.value2, // baseNode
                        rhs.mergeValue.value3, // zeroBits
                        rhs.mergeValue.value1 // zeroCount
                    )
                );
            }
            bytes32 hashValue = keccak256(
                abi.encode(MerkleTreeLib.MERGE_NORMAL, height, nodeKey, hashValueLeft, hashValueRight)
            );
            v.setValue(hashValue);
        }
    }

    function mergeWithZero(
        uint8 height,
        bytes32 nodeKey,
        MerkleTreeLib.MergeValue memory value,
        MerkleTreeLib.MergeValue memory v,
        bool setBit
    ) public pure {
        if (value.mergeType == MerkleTreeLib.MergeValueType.VALUE) {
            bytes32 zeroBits = setBit ? bytes32(0).setBit(MerkleTreeLib.MAX_TREE_LEVEL - height) : bytes32(0);
            bytes32 baseNode = hashBaseNode(height, nodeKey, value.mergeValue.value2);
            v.setMergeWithZero(1, baseNode, zeroBits);
        } else if (value.mergeType == MerkleTreeLib.MergeValueType.MERGE_WITH_ZERO) {
            bytes32 zeroBits = setBit
                ? value.mergeValue.value3.setBit(MerkleTreeLib.MAX_TREE_LEVEL - height)
                : value.mergeValue.value3;
            unchecked {
                v.setMergeWithZero(value.mergeValue.value1 + 1, value.mergeValue.value2, zeroBits);
            }
        } else {
            revert InvalidMergeValue();
        }
    }

    function hashBaseNode(uint8 height, bytes32 key, bytes32 value) public pure returns (bytes32) {
        return keccak256(abi.encode(height, key, value));
    }

    function calculateFirstMergeValue(
        MerkleTreeLib.MergeValue memory mergeValue,
        bytes32 key,
        bytes32 value,
        uint8 height
    ) internal pure {
        if (value.isZero() || height == 0) {
            return;
        }
        mergeValue.mergeType = MerkleTreeLib.MergeValueType.MERGE_WITH_ZERO;
        mergeValue.mergeValue.value1 = height;
        mergeValue.mergeValue.value2 = keccak256(abi.encode(0, key.parentPath(0), value));
        processNextLevel(mergeValue, key, MerkleTreeLib.MAX_TREE_LEVEL - height);
    }

    function processNextLevel(
        MerkleTreeLib.MergeValue memory mergeValue,
        bytes32 zeroBits,
        uint256 iReverse
    ) internal pure {
        if (zeroBits.getBit(iReverse)) {
            zeroBits = zeroBits.clearBit(iReverse);
        }

        if (iReverse == 0) {
            mergeValue.mergeValue.value3 = zeroBits;
            return;
        }

        processNextLevel(mergeValue, zeroBits, iReverse - 1);
    }
}
