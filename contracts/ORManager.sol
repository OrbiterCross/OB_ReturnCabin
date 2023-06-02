// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "./interface/IORManager.sol";
import "./interface/IORProtocal.sol";
import "./Multicall.sol";

contract ORManager is IORManager, Ownable, Multicall {
    mapping(uint16 => OperationsLib.ChainInfo) private _chains;
    mapping(address => bool) private _ebcs;
    address private _submitter;
    uint64 private _protocolFee;
    uint64 private _minChallengeRatio = 200;
    uint64 private _challengeUserRatio;
    uint64 private _feeChallengeSecond;
    uint64 private _feeTakeOnChallengeSecond;
    uint64 private _maxMDCLimit = 2 ** 64 - 1;

    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    // TODO: setting the same chainId or token affect the protocol?
    function registerChains(OperationsLib.ChainInfo[] calldata chains_) external onlyOwner {
        unchecked {
            for (uint i = 0; i < chains_.length; i++) {
                _chains[chains_[i].id] = chains_[i];
                emit ChainInfoUpdated(chains_[i].id, chains_[i]);
            }
        }
    }

    function updateChainSpvs(uint16 id, address[] calldata spvs, uint[] calldata indexs) external onlyOwner {
        unchecked {
            for (uint i = 0; i < spvs.length; i++) {
                if (i < indexs.length) {
                    _chains[id].spvs[indexs[i]] = spvs[i];
                } else {
                    _chains[id].spvs.push(spvs[i]);
                }
            }
        }
        emit ChainInfoUpdated(id, _chains[id]);
    }

    function updateChainTokens(
        uint16 id,
        OperationsLib.TokenInfo[] calldata tokens,
        uint[] calldata indexs
    ) external onlyOwner {
        unchecked {
            for (uint i = 0; i < tokens.length; i++) {
                if (i < indexs.length) {
                    _chains[id].tokens[indexs[i]] = tokens[i];
                } else {
                    _chains[id].tokens.push(tokens[i]);
                }
            }
        }
        emit ChainInfoUpdated(id, _chains[id]);
    }

    function getChainInfo(uint16 id) external view returns (OperationsLib.ChainInfo memory) {
        return _chains[id];
    }

    function ebcIncludes(address ebc) external view returns (bool) {
        return _ebcs[ebc];
    }

    function updateEbcs(address[] calldata ebcs_, bool[] calldata statuses) external onlyOwner {
        unchecked {
            for (uint i = 0; i < ebcs_.length; i++) {
                if (i < statuses.length) {
                    _ebcs[ebcs_[i]] = statuses[i];
                } else {
                    _ebcs[ebcs_[i]] = true;
                }
            }
        }
        emit EbcsUpdated(ebcs_, statuses);
    }

    function submitter() external view returns (address) {
        return _submitter;
    }

    function updateSubmitter(address submitter_) external onlyOwner {
        _submitter = submitter_;
        emit SubmitterFeeUpdated(_submitter);
    }

    function protocolFee() external view returns (uint64) {
        return _protocolFee;
    }

    function updateProtocolFee(uint64 protocolFee_) external onlyOwner {
        _protocolFee = protocolFee_;
        emit ProtocolFeeUpdated(_protocolFee);
    }

    function minChallengeRatio() external view returns (uint64) {
        return _minChallengeRatio;
    }

    function updateMinChallengeRatio(uint64 minChallengeRatio_) external onlyOwner {
        _minChallengeRatio = minChallengeRatio_;
        emit MinChallengeRatioUpdated(_minChallengeRatio);
    }

    function challengeUserRatio() external view returns (uint64) {
        return _challengeUserRatio;
    }

    function updateChallengeUserRatio(uint64 challengeUserRatio_) external onlyOwner {
        _challengeUserRatio = challengeUserRatio_;
        emit ChallengeUserRatioUpdated(_challengeUserRatio);
    }

    function feeChallengeSecond() external view returns (uint64) {
        return _feeChallengeSecond;
    }

    function updateFeeChallengeSecond(uint64 feeChallengeSecond_) external onlyOwner {
        _feeChallengeSecond = feeChallengeSecond_;
        emit FeeChallengeSecondUpdated(_feeChallengeSecond);
    }

    function feeTakeOnChallengeSecond() external view returns (uint64) {
        return _feeTakeOnChallengeSecond;
    }

    function updateFeeTakeOnChallengeSecond(uint64 feeTakeOnChallengeSecond_) external onlyOwner {
        _feeTakeOnChallengeSecond = feeTakeOnChallengeSecond_;
        emit FeeTakeOnChallengeSecondUpdated(_feeTakeOnChallengeSecond);
    }

    function maxMDCLimit() external view returns (uint64) {
        return _maxMDCLimit;
    }

    function updateMaxMDCLimit(uint64 maxMDCLimit_) external onlyOwner {
        _maxMDCLimit = maxMDCLimit_;
        emit MaxMDCLimitUpdated(_maxMDCLimit);
    }
}
