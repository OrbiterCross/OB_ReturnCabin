// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IORFeeManager {
    struct DealerInfo {
        uint256 feeRatio; // 1000,000 percent
        bytes32 extraInfoHash;
    }

    // feeMPTInfo
    struct Submission {
        uint64 startBlock;
        uint64 endBlock;
        uint64 submitTimestamp;
        bytes32 profitRoot;
        bytes32 stateTransTreeRoot;
    }

    enum ChallengeStatus {
        none,
        challengeDuration,
        challengeAccepted,
        challengeSuccess,
        challengeFail
    }

    enum FeeMangerDuration {
        lock,
        challenge,
        withdraw
    }

    event DealerUpdated(address indexed dealer, uint256 feeRatio, bytes extraInfo);

    event SubmitterRegistered(address indexed submitter, uint256 marginAmount);

    event SubmissionUpdated(
        uint64 startBlock,
        uint64 endBlock,
        uint64 indexed submitTimestamp,
        bytes32 indexed profitRoot,
        bytes32 indexed stateTransTreeRoot
    );
    event Withdraw(address indexed user, uint64 chainId, address token, uint256 debt, uint256 amount);

    event ETHDeposit(address indexed sender, uint256 amount);

    function registerSubmitter(uint256 marginAmount, address submitter) external;

    function submit(uint64 startBlock, uint64 endBlock, bytes32 profitRoot, bytes32 stateTransTreeRoot) external;

    /*
    function startChallenge(uint256 marginAmount, address challenger) external;

    function responsePositioning(bytes calldata response) external;

    function getCurrentBlockInfo() external view returns (Submission memory);
    */
}
