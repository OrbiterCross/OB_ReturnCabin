// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IORSpv.sol";

/// @title Simplified payment verification
/// @notice SPV proves that Source Tx has occurred in the Source Network.
contract ORSpv is IORSpv, Ownable {
    mapping(uint256 => bytes32) public makerTxTree;
    mapping(uint256 => bytes32) public userTxTree;

    // mapping(bytes32 => bool) public verifyRecordsee;

    // event ChangeTxTree(uint256 indexed chain, bytes32 root);
    /// @notice Set new transaction tree root hash
    /// @param chain Public chain ID
    /// @param root New root hash
    function setUserTxTreeRoot(uint256 chain, bytes32 root) external onlyOwner {
        userTxTree[chain] = root;
    }

    /// @notice Set the list of transactions for the market maker to delay payment collection roothash
    /// @param chain Public chain ID
    /// @param root New root hash
    function setMakerTxTreeRoot(uint256 chain, bytes32 root) external onlyOwner {
        makerTxTree[chain] = root;
    }

    // function setVerifyRecordsee(bytes32 txid) public onlyOwner {
    //     require(verifyRecordsee[txid] != true, "TxidVerified");
    //     verifyRecordsee[txid] = true;
    // }

    // function isVerify(bytes32 txid) public view returns (bool) {
    //     // bytes32 txid = SpvLib.calculationTxId(_txInfo);
    //     return verifyRecordsee[txid];
    // }

    /// @notice Transaction list of unpaid users
    /// @param _txInfo User transaction object
    /// @param _proof Transaction proof path
    /// @return Exist or fail to verify
    function verifyUserTxProof(OperationsLib.txInfo calldata _txInfo, bytes32[] calldata _proof)
        public
        view
        returns (bool)
    {
        bytes32 _leaf = keccak256(
            abi.encodePacked(
                _txInfo.lpid,
                _txInfo.chainID,
                _txInfo.txHash,
                _txInfo.sourceAddress,
                _txInfo.destAddress,
                _txInfo.nonce,
                _txInfo.amount,
                _txInfo.tokenAddress,
                _txInfo.timestamp
            )
        );
        return SpvLib.verify(userTxTree[_txInfo.chainID], _leaf, _proof);
    }

    /// @notice List of merchant transactions with delayed payment
    /// @param _txInfo User transaction object
    /// @param _proof Transaction proof path
    /// @return Exist or fail to verify
    function verifyMakerTxProof(OperationsLib.txInfo calldata _txInfo, bytes32[] calldata _proof)
        public
        view
        returns (bool)
    {
        bytes32 _leaf = keccak256(
            abi.encodePacked(
                _txInfo.lpid,
                _txInfo.chainID,
                _txInfo.txHash,
                _txInfo.sourceAddress,
                _txInfo.destAddress,
                _txInfo.nonce,
                _txInfo.amount,
                _txInfo.tokenAddress,
                _txInfo.timestamp
            )
        );
        return SpvLib.verify(makerTxTree[_txInfo.chainID], _leaf, _proof);
    }
}
