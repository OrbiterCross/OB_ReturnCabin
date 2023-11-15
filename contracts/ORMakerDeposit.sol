// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IORMakerDeposit} from "./interface/IORMakerDeposit.sol";
import {IORManager} from "./interface/IORManager.sol";
import {IORMDCFactory} from "./interface/IORMDCFactory.sol";
import {IORChallengeSpv} from "./interface/IORChallengeSpv.sol";
import {IOREventBinding} from "./interface/IOREventBinding.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {HelperLib} from "./library/HelperLib.sol";
import {RuleLib} from "./library/RuleLib.sol";
import {ConstantsLib} from "./library/ConstantsLib.sol";
import {BridgeLib} from "./library/BridgeLib.sol";
import {VersionAndEnableTime} from "./VersionAndEnableTime.sol";
import {IVerifierRouter} from "./zkp/IVerifierRouter.sol";

contract ORMakerDeposit is IORMakerDeposit, VersionAndEnableTime {
    using HelperLib for uint256[];
    using HelperLib for address[];
    using HelperLib for bytes;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    // VersionAndEnableTime._version and _enableTime use a slot

    // Warning: the following order and type changes will cause state verification changes
    address private _owner;
    IORMDCFactory private _mdcFactory;
    bytes32 private _columnArrayHash;
    mapping(uint64 => address) private _spvs; // chainId => spvAddress
    bytes32 private _responseMakersHash; // hash(response maker list), not just owner, to improve tps
    mapping(address => RuleLib.RootWithVersion) private _rulesRoots; // ebc => merkleRoot(rules), version
    mapping(bytes32 => uint256) private _pledgeBalances; // hash(ebc, sourceChainId, sourceToken) => pledgeBalance
    mapping(address => uint256) private _freezeAssets; // token(ETH: 0) => freezeAmount
    mapping(bytes32 => ChallengeInfo) private _challenges; // hash(sourceChainId, transactionHash) => ChallengeInfo
    mapping(address => WithdrawRequestInfo) private _withdrawRequestInfo;
    mapping(uint256 => ChallengeNode) private _challengeNodeList;
    uint256 private _challengeNodeHead;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyNoRequestTimestamp(address requestToken) {
        require(_withdrawRequestInfo[requestToken].requestTimestamp == 0, "RHB");
        _;
    }

    modifier onlyRequestTimestampCheckPass(address requestToken) {
        require(
            _withdrawRequestInfo[requestToken].requestTimestamp > 0 &&
                block.timestamp >= _withdrawRequestInfo[requestToken].requestTimestamp,
            "WTN"
        );
        _;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function initialize(address owner_) external {
        require(_owner == address(0), "_ONZ");
        require(owner_ != address(0), "OZ");

        _owner = owner_;
        _mdcFactory = IORMDCFactory(msg.sender);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function mdcFactory() external view returns (address) {
        return address(_mdcFactory);
    }

    function columnArrayHash() external view returns (bytes32) {
        return _columnArrayHash;
    }

    function updateColumnArray(
        uint64 enableTime,
        address[] calldata dealers,
        address[] calldata ebcs,
        uint64[] calldata chainIds
    ) external onlyOwner {
        versionIncreaseAndEnableTime(enableTime);

        require(dealers.length < 100 && ebcs.length < 10 && chainIds.length < 100, "DECOF");

        IORManager manager = IORManager(_mdcFactory.manager());
        for (uint256 i = 0; i < ebcs.length; ) {
            require(manager.ebcIncludes(ebcs[i]), "EI"); // Has invalid ebc

            unchecked {
                i++;
            }
        }

        for (uint256 i = 0; i < chainIds.length; ) {
            BridgeLib.ChainInfo memory chainInfo = manager.getChainInfo(chainIds[i]);
            require(chainInfo.id > 0, "CI"); // Invalid chainId

            unchecked {
                i++;
            }
        }

        _columnArrayHash = abi.encode(dealers, ebcs, chainIds).hash();
        emit ColumnArrayUpdated(_mdcFactory.implementation(), _columnArrayHash, dealers, ebcs, chainIds);
    }

    function spv(uint64 chainId) external view returns (address) {
        return _spvs[chainId];
    }

    function updateSpvs(uint64 enableTime, address[] calldata spvs, uint64[] calldata chainIds) external onlyOwner {
        versionIncreaseAndEnableTime(enableTime);

        IORManager manager = IORManager(_mdcFactory.manager());
        address impl = _mdcFactory.implementation();

        for (uint256 i = 0; i < chainIds.length; i++) {
            BridgeLib.ChainInfo memory chainInfo = manager.getChainInfo(chainIds[i]);
            require(chainInfo.id > 0, "CI"); // Invalid chainId
            require(chainInfo.spvs.includes(spvs[i]), "SI"); // Invalid spv

            _spvs[chainIds[i]] = spvs[i];

            emit SpvUpdated(impl, chainIds[i], spvs[i]);
        }
    }

    function responseMakersHash() external view returns (bytes32) {
        return _responseMakersHash;
    }

    function updateResponseMakers(uint64 enableTime, bytes[] calldata responseMakerSignatures) external onlyOwner {
        versionIncreaseAndEnableTime(enableTime);

        bytes32 data = abi.encode(address(this)).hash();

        uint256[] memory responseMakers_ = new uint256[](responseMakerSignatures.length);
        for (uint256 i = 0; i < responseMakerSignatures.length; i++) {
            responseMakers_[i] = uint256(uint160(data.toEthSignedMessageHash().recover(responseMakerSignatures[i])));
        }

        _responseMakersHash = abi.encode(responseMakers_).hash();
        emit ResponseMakersUpdated(_mdcFactory.implementation(), responseMakers_);
    }

    function freezeAssets(address token) external view returns (uint256) {
        return _freezeAssets[token];
    }

    function deposit(address token, uint256 amount) external payable {
        // TODO: This method is useless if it does not need to throw an event
        // ETH received by default
        // ERC20 calls safeTransferFrom, can also call `transfer` send assets to address(this)
        if (token != address(0)) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function getWithdrawRequestInfo(address targetToken) external view returns (WithdrawRequestInfo memory) {
        return _withdrawRequestInfo[targetToken];
    }

    function withdrawRequest(
        address requestToken,
        uint256 requestAmount
    ) external onlyOwner onlyNoRequestTimestamp(requestToken) {
        uint64 requestTimestamp = uint64(
            block.timestamp + IORManager(_mdcFactory.manager()).getChallengeWithdrawDelay()
        );
        _withdrawRequestInfo[requestToken] = WithdrawRequestInfo(requestAmount, requestTimestamp, requestToken);
        emit WithdrawRequested(requestAmount, requestTimestamp, requestToken);
    }

    function withdraw(address token) external onlyOwner onlyRequestTimestampCheckPass(token) {
        WithdrawRequestInfo storage requestInfo = _withdrawRequestInfo[token];
        requestInfo.requestTimestamp = 0;

        uint256 balance;
        if (token == address(0)) {
            balance = address(this).balance - _freezeAssets[requestInfo.requestToken];

            require(balance >= requestInfo.requestAmount, "ETH: IF");

            (bool sent, ) = payable(msg.sender).call{value: requestInfo.requestAmount}("");

            require(sent, "ETH: SE");
        } else {
            balance =
                IERC20(requestInfo.requestToken).balanceOf(address(this)) -
                _freezeAssets[requestInfo.requestToken];

            require(balance >= requestInfo.requestAmount, "ERC20: IF");

            IERC20(requestInfo.requestToken).safeTransfer(msg.sender, requestInfo.requestAmount);
        }
    }

    function rulesRoot(address ebc) external view returns (RuleLib.RootWithVersion memory) {
        return _rulesRoots[ebc];
    }

    function updateRulesRoot(
        uint64 enableTime,
        address ebc,
        RuleLib.Rule[] calldata rules,
        RuleLib.RootWithVersion calldata rootWithVersion,
        uint64[] calldata sourceChainIds,
        uint256[] calldata pledgeAmounts
    ) external payable onlyOwner {
        versionIncreaseAndEnableTime(enableTime);

        _updateRulesRoot(ebc, rules, rootWithVersion);

        require(sourceChainIds.length == pledgeAmounts.length, "SPL");

        uint256 increaseAmount;
        for (uint256 i = 0; i < sourceChainIds.length; ) {
            // TODO: Must save pledge amount by sourceChainId?
            //       Is it feasible to only by token?
            bytes32 k = abi.encode(ebc, sourceChainIds[i], address(0)).hash();

            if (pledgeAmounts[i] > _pledgeBalances[k]) {
                uint256 _d = pledgeAmounts[i] - _pledgeBalances[k];
                increaseAmount += _d;
            }

            _pledgeBalances[k] = pledgeAmounts[i];

            unchecked {
                i++;
            }
        }

        require(increaseAmount <= msg.value, "IV"); // Insufficient value
    }

    function updateRulesRootERC20(
        uint64 enableTime,
        address ebc,
        RuleLib.Rule[] calldata rules,
        RuleLib.RootWithVersion calldata rootWithVersion,
        uint64[] calldata sourceChainIds,
        uint256[] calldata pledgeAmounts,
        address token
    ) external onlyOwner {
        versionIncreaseAndEnableTime(enableTime);

        _updateRulesRoot(ebc, rules, rootWithVersion);

        require(sourceChainIds.length == pledgeAmounts.length, "SPL");

        for (uint256 i = 0; i < sourceChainIds.length; ) {
            bytes32 k = abi.encode(ebc, sourceChainIds[i], token).hash();

            if (pledgeAmounts[i] > _pledgeBalances[k]) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), pledgeAmounts[i] - _pledgeBalances[k]);
            }

            unchecked {
                i++;
            }
        }
    }

    function _updateRulesRoot(
        address ebc,
        RuleLib.Rule[] calldata rules,
        RuleLib.RootWithVersion calldata rootWithVersion
    ) private {
        for (uint256 i = 0; i < rules.length; ) {
            RuleLib.checkChainIds(rules[i].chainId0, rules[i].chainId1);
            RuleLib.checkWithholdingFees(rules[i].withholdingFee0, rules[i].withholdingFee1);

            unchecked {
                i++;
            }
        }

        IORManager manager = IORManager(_mdcFactory.manager());
        require(manager.ebcIncludes(ebc), "EI"); // Invalid ebc

        require(rootWithVersion.root != bytes32(0), "RZ");
        unchecked {
            require(_rulesRoots[ebc].version + 1 == rootWithVersion.version, "VE");
        }

        _rulesRoots[ebc] = rootWithVersion;

        emit RulesRootUpdated(_mdcFactory.implementation(), ebc, rootWithVersion);
    }

    function _addChallengeNode(uint256 parentNodeNumOfTargetNode, uint256 challengeIdentNum) private {
        ChallengeNode storage challengeNode = _challengeNodeList[challengeIdentNum];
        uint64 currentTime = uint64(block.timestamp);

        if (challengeIdentNum > _challengeNodeHead) {
            challengeNode.prev = _challengeNodeHead;
            challengeNode.challengeCreateTime = currentTime;
            _challengeNodeHead = challengeIdentNum;
        } else {
            ChallengeNode storage parentChallengeNode = _challengeNodeList[parentNodeNumOfTargetNode];
            require(
                parentChallengeNode.challengeCreateTime > 0 &&
                    parentNodeNumOfTargetNode > challengeIdentNum &&
                    challengeIdentNum > parentChallengeNode.prev,
                "VLNP"
            );

            challengeNode.prev = parentChallengeNode.prev;
            challengeNode.challengeCreateTime = currentTime;
            parentChallengeNode.prev = challengeIdentNum;
        }
    }

    function canChallengeContinue(uint256 challengeIdentNum) external view returns (bool) {
        return _canChallengeContinue(challengeIdentNum);
    }

    function _canChallengeContinue(uint256 challengeIdentNum) private view returns (bool) {
        ChallengeNode memory currChallengeNode = _challengeNodeList[challengeIdentNum];
        require(currChallengeNode.challengeCreateTime > 0, "UCY");

        bool makerNotResponded = currChallengeNode.challengeFinished == false;
        if (currChallengeNode.prev == 0) {
            return makerNotResponded;
        } else {
            bool prevMakerResponded = _challengeNodeList[currChallengeNode.prev].challengeFinished == true;
            return makerNotResponded && prevMakerResponded;
        }
    }

    function challenge(
        uint64 sourceTxTime,
        uint64 sourceChainId,
        uint64 sourceTxBlockNum,
        uint64 sourceTxIndex,
        bytes32 sourceTxHash,
        address freezeToken,
        uint256 freezeAmount1,
        uint256 parentNodeNumOfTargetNode
    ) external payable {
        uint256 startGasNum = gasleft();
        bytes32 challengeId = abi.encode(sourceChainId, sourceTxHash).hash();
        // Submit challenge before the winner is decided
        require(_challenges[challengeId].result.winner == address(0), "CE");
        // Make sure the source timestamp is before the challenge
        require(uint64(block.timestamp) >= sourceTxTime, "STOF");

        require(_challenges[challengeId].statement[msg.sender].challengeTime == 0, "CT");

        uint256 freezeAmount0 = freezeAmount1;

        if (freezeToken == address(0)) {
            require(msg.value == (freezeAmount1 + ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT), "IF+MD");
            _freezeAssets[freezeToken] += freezeAmount0 + freezeAmount1 + ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT;
        } else {
            require(msg.value == ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT, "IF");
            IERC20(freezeToken).safeTransferFrom(msg.sender, address(this), freezeAmount1);
            _freezeAssets[freezeToken] += freezeAmount0 + freezeAmount1;
        }

        uint256 challengeIdentNum = HelperLib.calculateChallengeIdentNum(
            sourceTxTime,
            sourceChainId,
            sourceTxBlockNum,
            sourceTxIndex
        );

        // For more challenger challenge the same tx, the same challenge will pass
        if (_challengeNodeList[challengeIdentNum].challengeCreateTime == 0) {
            _addChallengeNode(parentNodeNumOfTargetNode, challengeIdentNum);
        }

        // TODO: Currently it is assumed that the pledged assets of the challenger and the owner are the same

        // Freeze mdc's owner assets and the assets in of challenger
        uint128 challengeGasPrice = uint128(block.basefee + IORManager(_mdcFactory.manager()).getPriorityFee());

        _challenges[challengeId].statement[msg.sender] = ChallengeStatement({
            sourceTxFrom: 0,
            sourceTxTime: sourceTxTime,
            freezeToken: freezeToken,
            challengeUserRatio: 0,
            freezeAmount0: freezeAmount0,
            freezeAmount1: freezeAmount1,
            challengeTime: uint64(block.timestamp),
            abortTime: 0,
            sourceTxBlockNum: sourceTxBlockNum,
            sourceTxIndex: sourceTxIndex,
            challengerVerifyTransactionFee: challengeGasPrice
        });
        emit ChallengeInfoUpdated({
            challengeId: challengeId,
            statement: _challenges[challengeId].statement[msg.sender],
            result: _challenges[challengeId].result
        });
        _challenges[challengeId].statement[msg.sender].challengerVerifyTransactionFee *= uint128(
            startGasNum - gasleft()
        );
    }

    function checkChallenge(uint64 sourceChainId, bytes32 sourceTxHash, address[] calldata challenger) external {
        bytes32 challengeId = abi.encode(uint64(sourceChainId), sourceTxHash).hash();
        uint256 challengeIdentNum;
        ChallengeInfo storage challengeInfo = _challenges[challengeId];
        ChallengeStatement memory winnerStatement = challengeInfo.statement[challengeInfo.result.winner];
        ChallengeResult memory result = challengeInfo.result;
        IORManager manager = IORManager(_mdcFactory.manager());
        BridgeLib.ChainInfo memory chainInfo = manager.getChainInfo(sourceChainId);

        for (uint256 i = 0; ; ) {
            ChallengeStatement memory challengeStatement = challengeInfo.statement[challenger[i]];

            // Make sure the challenge exists
            require(challengeStatement.challengeTime > 0, "CNE");

            require(challengeStatement.abortTime == 0, "CA");

            challengeIdentNum = HelperLib.calculateChallengeIdentNum(
                challengeStatement.sourceTxTime,
                sourceChainId,
                challengeStatement.sourceTxBlockNum,
                challengeStatement.sourceTxIndex
            );

            // For more challenger challenge the same tx, the same challenge will pass
            if (_challengeNodeList[challengeIdentNum].challengeFinished == false) {
                require(_canChallengeContinue(challengeIdentNum), "NCCF");
            }

            if (result.verifiedTime1 > 0) {
                // maker verified! all challenger fail
                _unFreezeToken(
                    challengeStatement.freezeToken,
                    _challengerFailed(challengeStatement, challengeIdentNum)
                );
            } else {
                if (result.verifiedTime0 > 0) {
                    // challenger verified! maker over time, maker fail
                    require(block.timestamp > chainInfo.maxVerifyChallengeDestTxSecond + result.verifiedTime0, "VCST");
                    _unFreezeToken(
                        challengeStatement.freezeToken,
                        _makerFailed(challengeStatement, winnerStatement, result, challenger[i], sourceChainId)
                    );
                } else {
                    // none challenger verify
                    require(
                        block.timestamp > chainInfo.maxVerifyChallengeSourceTxSecond + challengeStatement.sourceTxTime,
                        "VDST"
                    );
                    _unFreezeToken(
                        challengeStatement.freezeToken,
                        _challengerFailed(challengeStatement, challengeIdentNum)
                    );
                }
            }

            challengeInfo.statement[challenger[i]].abortTime = uint64(block.timestamp);

            emit ChallengeInfoUpdated({
                challengeId: challengeId,
                statement: challengeInfo.statement[challenger[i]],
                result: result
            });

            if (i == challenger.length - 1) {
                break;
            }

            unchecked {
                i += 1;
            }
        }
        _freezeAssets[address(0)] -= challenger.length * ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT;
    }

    function _parsePublicInput(bytes calldata proofData) private pure returns (PublicInputData memory) {
        return
            PublicInputData({
                tx_hash: bytes32((uint256(bytes32(proofData[448:480])) << 128) | uint256(bytes32(proofData[480:512]))),
                chain_id: uint64(uint256(bytes32(proofData[512:544]))),
                index: uint256(bytes32(proofData[544:576])),
                from: uint256(bytes32(proofData[576:608])),
                to: uint160(uint256(bytes32(proofData[608:640]))),
                token: address(uint160(uint256(bytes32(proofData[640:672])))),
                amount: uint256(bytes32(proofData[672:704])),
                nonce: uint256(bytes32(proofData[704:736])),
                time_stamp: uint256(bytes32(proofData[736:768])),
                dest: uint160(uint256(bytes32(proofData[768:800]))),
                dest_token: uint160(uint256(bytes32(proofData[800:832]))),
                l1_tx_block_hash: bytes32(
                    (uint256(bytes32(proofData[384:416])) << 128) | uint256(bytes32(proofData[416:448]))
                ),
                l1_tx_block_number: uint256(bytes32(proofData[896:928])),
                mdc_contract_address: address(uint160(uint256(bytes32(proofData[1120:1152])))),
                manager_contract_address: address(uint160(uint256(bytes32(proofData[1152:1184])))),
                mdc_rule_root_slot: (uint256(bytes32(proofData[1184:1216])) << 128) |
                    uint256(bytes32(proofData[1216:1248])),
                mdc_rule_version_slot: (uint256(bytes32(proofData[1248:1280])) << 128) |
                    uint256(bytes32(proofData[1280:1312])),
                mdc_rule_enable_time_slot: (uint256(bytes32(proofData[1312:1344])) << 128) |
                    uint256(bytes32(proofData[1344:1376])),
                mdc_column_array_hash_slot: bytes32(
                    (uint256(bytes32(proofData[1376:1408])) << 128) | uint256(bytes32(proofData[1408:1440]))
                ),
                mdc_response_makers_hash_slot: bytes32(
                    (uint256(bytes32(proofData[1440:1472])) << 128) | uint256(bytes32(proofData[1472:1504]))
                ),
                manage_source_chain_info_slot: bytes32(
                    (uint256(bytes32(proofData[1504:1536])) << 128) | uint256(bytes32(proofData[1536:1568]))
                ),
                manage_source_chain_mainnet_token_info_slot: bytes32(
                    (uint256(bytes32(proofData[1568:1600])) << 128) | uint256(bytes32(proofData[1600:1632]))
                ),
                manage_dest_chain_mainnet_token_slot: bytes32(
                    (uint256(bytes32(proofData[1632:1664])) << 128) | uint256(bytes32(proofData[1664:1696]))
                ),
                manage_challenge_user_ratio_slot: bytes32(
                    (uint256(bytes32(proofData[1696:1728])) << 128) | uint256(bytes32(proofData[1728:1760]))
                ),
                mdc_pre_rule_root: bytes32(
                    (uint256(bytes32(proofData[1760:1792])) << 128) | uint256(bytes32(proofData[1792:1824]))
                ),
                mdc_pre_rule_version: uint256(bytes32(proofData[1824:1856]) << 128) |
                    uint256(bytes32(proofData[1856:1888])),
                mdc_pre_rule_enable_time: uint64(bytes8(proofData[1904:1912])),
                mdc_pre_column_array_hash: bytes32(
                    (uint256(bytes32(proofData[1952:1984])) << 128) | uint256(bytes32(proofData[1984:2016]))
                ),
                mdc_pre_response_makers_hash: ((uint256(bytes32(proofData[2016:2048])) << 128) |
                    uint256(bytes32(proofData[2048:2080]))),
                // manage_pre_source_chain_info: bytes32(
                //     (uint256(bytes32(proofData[2080:2112])) << 128) | uint256(bytes32(proofData[2112:2144]))
                // ),
                manage_pre_source_chain_max_verify_challenge_source_tx_second: uint64(bytes8(proofData[2128:2136])),
                manage_pre_source_chain_min_verify_challenge_source_tx_second: uint64(bytes8(proofData[2136:2144])),
                manage_pre_source_chain_max_verify_challenge_dest_tx_second: uint64(bytes8(proofData[2096:2104])),
                manage_pre_source_chain_min_verify_challenge_dest_tx_second: uint64(bytes8(proofData[2104:2112])),
                manage_pre_source_chain_mainnet_token: address(
                    uint160(uint256(bytes32(proofData[2144:2176]) << 128) | uint256(bytes32(proofData[2176:2208])))
                ),
                manage_pre_dest_chain_mainnet_token: address(
                    uint160(uint256(bytes32(proofData[2208:2240]) << 128) | uint256(bytes32(proofData[2240:2272])))
                ),
                manage_pre_challenge_user_ratio: uint64(bytes8(proofData[2320:2328])),
                mdc_current_rule_root: bytes32(
                    (uint256(bytes32(proofData[2336:2368])) << 128) | uint256(bytes32(proofData[2368:2400]))
                ),
                mdc_current_rule_version: uint256(bytes32(proofData[2400:2432]) << 128) |
                    uint256(bytes32(proofData[2432:2464])),
                mdc_current_rule_enable_time: uint64(bytes8(proofData[2480:2488])),
                source_chain_id: uint256(bytes32(proofData[2528:2560])),
                source_token: address(uint160(uint256(bytes32(proofData[2560:2592])))),
                source_min_price: uint256(bytes32(proofData[2592:2624])),
                source_max_price: uint256(bytes32(proofData[2624:2656])),
                source_with_holding_fee: uint256(bytes32(proofData[2656:2688])),
                source_trading_fee: uint256(bytes32(proofData[2688:2720])),
                source_response_time: uint256(bytes32(proofData[2720:2752])),
                dest_chain_id: uint256(bytes32(proofData[2752:2784])),
                dest_token_rule: ((uint256(bytes32(proofData[2784:2816])))),
                dest_min_price: uint256(bytes32(proofData[2816:2848])),
                dest_max_price: uint256(bytes32(proofData[2848:2880])),
                dest_with_holding_fee: uint256(bytes32(proofData[2880:2912])),
                dest_trading_fee: uint256(bytes32(proofData[2912:2944])),
                dest_response_time: uint256(bytes32(proofData[2944:2976])),
                ob_contracts_pre_block_hash: bytes32(
                    (uint256(bytes32(proofData[928:960])) << 128) | uint256(bytes32(proofData[960:992]))
                ),
                ob_contracts_pre_block_number: uint256(bytes32(proofData[992:1024])),
                ob_contracts_current_block_hash: bytes32(
                    (uint256(bytes32(proofData[1024:1056])) << 128) | uint256(bytes32(proofData[1056:1088]))
                ),
                ob_contracts_current_block_number: uint256(bytes32(proofData[1088:1120]))
            });
    }

    function verifyChallengeSource(
        address challenger,
        // bytes calldata publicInput, // TODO: Enable this parameter after the circuit has finished hash-encoding the public input.
        PublicInputData calldata publicInputData,
        bytes calldata proof,
        bytes calldata rawDatas
    ) external {
        uint256 startGasNum = gasleft();
        PublicInputData memory publicInputData2 = _parsePublicInput(proof);
        (proof);
        (publicInputData2);
        require(
            (publicInputData.manager_contract_address == _mdcFactory.manager()) &&
                (publicInputData.mdc_contract_address == address(this)),
            "MCE"
        );
        BridgeLib.ChainInfo memory chainInfo = IORManager(publicInputData.manager_contract_address).getChainInfo(
            publicInputData.chain_id
        );

        require(
            IORChallengeSpv(chainInfo.spvs[chainInfo.spvs.length - 1]).verifySourceTx(proof, publicInputData.chain_id),
            "VF"
        );
        // Check chainId, hash, timestamp
        bytes32 challengeId = abi.encode(publicInputData.chain_id, publicInputData.tx_hash).hash();
        ChallengeStatement memory statement = _challenges[challengeId].statement[challenger];
        ChallengeResult memory result = _challenges[challengeId].result;
        require(statement.challengeTime > 0, "CTZ");
        require(result.verifiedTime0 == 0, "VT0NZ");
        // Check timestamp
        require(publicInputData.time_stamp == statement.sourceTxTime, "ST");
        // Check maker address
        require(uint160(publicInputData.to) == uint160(_owner), "TNEO");
        // Check freezeToken
        require(statement.freezeToken == publicInputData.token, "FTV");
        // Check FreezeAmount
        require(statement.freezeAmount1 == publicInputData.amount, "FALV");

        // Check manager's chainInfo.minVerifyChallengeSourceTxSecond,maxVerifyChallengeSourceTxSecond
        {
            uint256 timeDiff = block.timestamp - publicInputData.time_stamp;
            require(
                timeDiff >= publicInputData.manage_pre_source_chain_min_verify_challenge_source_tx_second,
                "MINTOF"
            );
            require(
                timeDiff <= publicInputData.manage_pre_source_chain_max_verify_challenge_source_tx_second,
                "MAXTOF"
            );
        }
        (
            address[] memory dealers,
            address[] memory ebcs,
            uint64[] memory chainIds,
            address ebc,
            RuleLib.Rule memory rule
        ) = abi.decode(rawDatas, (address[], address[], uint64[], address, RuleLib.Rule));
        // check _columnArrayHash
        require(abi.encode(dealers, ebcs, chainIds).hash() == publicInputData.mdc_pre_column_array_hash, "CHE");

        // Check ebc address, destChainId, destToken
        uint256 destChainId;
        {
            IOREventBinding.AmountParams memory ap = IOREventBinding(ebc).getAmountParams(publicInputData.amount);
            require(ebc == ebcs[ap.ebcIndex - 1], "ENE");

            require(ap.chainIdIndex <= chainIds.length, "COF");
            destChainId = chainIds[ap.chainIdIndex - 1];
            require(destChainId == publicInputData.dest_chain_id, "DCI");

            require(
                uint160(statement.freezeToken) == uint160(publicInputData.manage_pre_dest_chain_mainnet_token),
                "DTV"
            );
        }

        // Check rule & enabletime slot, rule hash
        {
            uint256 slot = uint256(abi.encode(ebc, 6).hash());
            require(slot == publicInputData.mdc_rule_root_slot, "RRSE");
            require((slot + 1) == publicInputData.mdc_rule_version_slot, "RVSE");
            require(0 == publicInputData.mdc_rule_enable_time_slot, "RVSE");
            // Check rule hash
            require((abi.encode(rule).hash()) == publicInputData.mdc_pre_rule_root, "RH");
        }

        // Check dest amount
        // TODO: Is there a more general solution. Not only amount
        RuleLib.RuleOneway memory ro = RuleLib.convertToOneway(rule, publicInputData.chain_id);
        uint256 destAmount = IOREventBinding(ebc).getResponseAmountFromIntent(
            IOREventBinding(ebc).getResponseIntent(publicInputData.amount, ro)
        );

        ChallengeStatement storage statement_s = _challenges[challengeId].statement[challenger];
        ChallengeResult storage result_s = _challenges[challengeId].result;

        // Save tx'from address, and compensate tx'from on the mainnet when the maker failed
        statement_s.sourceTxFrom = publicInputData.from;

        statement_s.challengeUserRatio = publicInputData.manage_pre_challenge_user_ratio;

        result_s.verifiedTime0 = uint64(block.timestamp);

        result_s.winner = challenger;

        // Save verified data's hash.
        // [minVerifyChallengeDestTxSecond, maxVerifyChallengeDestTxSecond, nonce, destChainId, destAddress, destToken, destAmount, responeMakersHash]
        result_s.verifiedDataHash0 = abi
            .encode(
                [
                    publicInputData.manage_pre_source_chain_min_verify_challenge_dest_tx_second,
                    publicInputData.manage_pre_source_chain_max_verify_challenge_dest_tx_second,
                    publicInputData.nonce,
                    destChainId,
                    publicInputData.from,
                    ro.destToken,
                    destAmount,
                    publicInputData.mdc_pre_response_makers_hash
                ]
            )
            .hash();
        emit ChallengeInfoUpdated({challengeId: challengeId, statement: statement_s, result: result_s});
        // TODO: add verify source gas cost (solt & emit)
        uint128 actualGasPrice = uint128(block.basefee + IORManager(_mdcFactory.manager()).getPriorityFee());
        statement_s.challengerVerifyTransactionFee +=
            uint128((startGasNum - gasleft() + IORManager(_mdcFactory.manager()).getChallengeGasUsed())) *
            actualGasPrice;
    }

    function _parsePublicInputDest(bytes calldata proofData) private pure returns (PublicInputDataDest memory) {
        uint256 ProofLength = 384;
        uint256 splitStep = 32;
        uint256 splitStart = ProofLength + 64; // 384 is proof length;64 is blockHash length
        uint256 TrackBlockSplitStart = splitStart + splitStep * 12;
        return
            PublicInputDataDest({
                txHash: bytes32(
                    (uint256(bytes32(proofData[splitStart:splitStart + splitStep])) << 128) |
                        uint256(bytes32(proofData[splitStart + splitStep:splitStart + splitStep * 2]))
                ),
                chainId: uint64(uint256(bytes32(proofData[splitStart + splitStep * 3:splitStart + splitStep * 4]))),
                txIndex: uint256(bytes32(proofData[splitStart + splitStep * 2:splitStart + splitStep * 3])),
                from: ((uint256(bytes32(proofData[splitStart + splitStep * 4:splitStart + splitStep * 5])))),
                to: ((uint256(bytes32(proofData[splitStart + splitStep * 5:splitStart + splitStep * 6])))),
                token: ((uint256(bytes32(proofData[splitStart + splitStep * 6:splitStart + splitStep * 7])))),
                amount: uint256(bytes32(proofData[splitStart + splitStep * 7:splitStart + splitStep * 8])),
                nonce: uint256(bytes32(proofData[splitStart + splitStep * 8:splitStart + splitStep * 9])),
                timestamp: uint64(uint256(bytes32(proofData[splitStart + splitStep * 9:splitStart + splitStep * 10]))),
                L1TXBlockHash: bytes32(
                    (uint256(bytes32(proofData[TrackBlockSplitStart:TrackBlockSplitStart + splitStep])) << 128) |
                        uint256(
                            bytes32(proofData[TrackBlockSplitStart + splitStep:TrackBlockSplitStart + splitStep * 2])
                        )
                ),
                L1TBlockNumber: uint256(
                    bytes32(proofData[TrackBlockSplitStart + splitStep * 2:TrackBlockSplitStart + splitStep * 3])
                )
            });
    }

    function verifyChallengeDest(
        address challenger,
        uint64 sourceChainId,
        bytes32 sourceTxHash,
        // bytes calldata publicInput, // TODO: Enable this parameter after the circuit has finished hash-encoding the public input.
        bytes calldata proof,
        uint256[] calldata verifiedData0,
        bytes calldata rawDatas
    ) external {
        // parse Public input
        PublicInputDataDest memory publicInputData = _parsePublicInputDest(proof);
        // get DestChainInfo
        BridgeLib.ChainInfo memory chainInfo = IORManager(_mdcFactory.manager()).getChainInfo(sourceChainId);
        require(IORChallengeSpv(chainInfo.spvs[chainInfo.spvs.length - 1]).verifyDestTx(proof), "VF");
        bytes32 challengeId = abi.encode(sourceChainId, sourceTxHash).hash();
        ChallengeStatement memory statement = _challenges[challengeId].statement[challenger];
        ChallengeResult memory result = _challenges[challengeId].result;
        require(result.winner == challenger, "WNE");
        require(result.verifiedTime0 > 0, "VT0Z");
        require(result.verifiedTime1 == 0, "VT1NZ");

        require(
            _canChallengeContinue(
                HelperLib.calculateChallengeIdentNum(
                    statement.sourceTxTime,
                    sourceChainId,
                    statement.sourceTxBlockNum,
                    statement.sourceTxIndex
                )
            ),
            "NCCF"
        );

        // Parse rawDatas
        uint256[] memory responseMakers = abi.decode(rawDatas, (uint256[]));

        // Check verifiedData0
        require(abi.encode(verifiedData0).hash() == _challenges[challengeId].result.verifiedDataHash0, "VDH0");
        require(abi.encode(responseMakers).hash() == bytes32(verifiedData0[7]), "RMH");

        // Check minVerifyChallengeDestTxSecond, maxVerifyChallengeDestTxSecond
        // TODO: make this public input
        {
            uint256 timeDiff = block.timestamp - result.verifiedTime0;
            require(timeDiff >= uint64(chainInfo.minVerifyChallengeDestTxSecond), "MINTOF");
            require(timeDiff <= uint64(chainInfo.maxVerifyChallengeDestTxSecond), "MAXTOF");
        }

        // Check dest chainId
        require(verifiedData0[3] == publicInputData.chainId, "DCID");

        // Check dest from address in responseMakers
        require(responseMakers.includes(publicInputData.from), "MIC");

        // Check dest address
        require(verifiedData0[4] == publicInputData.to, "DADDR");

        // Check dest token
        require(verifiedData0[5] == publicInputData.token, "DT");

        // Check dest amount (Warning: The nonce is at the end of the amount)
        require(verifiedData0[6] - verifiedData0[2] == publicInputData.amount, "DT");

        // TODO: check responseTime. Source tx timestamp may be more than dest tx timestamp.

        _challenges[challengeId].result.verifiedTime1 = uint64(block.timestamp);

        emit ChallengeInfoUpdated({
            challengeId: challengeId,
            statement: _challenges[challengeId].statement[msg.sender],
            result: _challenges[challengeId].result
        });
    }

    function _challengerFailed(
        ChallengeStatement memory challengeInfo,
        uint256 challengeIdentNum
    ) internal returns (uint256 unFreezeAmount) {
        unFreezeAmount = (challengeInfo.freezeAmount0 + challengeInfo.freezeAmount1 + MIN_CHALLENGE_DEPOSIT_AMOUNT);
        _challengeNodeList[challengeIdentNum].challengeFinished = true;
    }

    function _unFreezeToken(address freezeToken, uint256 unFreezeAmount) internal {
        // Unfreeze
        if (unFreezeAmount > 0) {
            _freezeAssets[freezeToken] -= unFreezeAmount;
        }
    }

    function _makerFailed(
        ChallengeStatement memory challengeInfo,
        ChallengeStatement memory challengeInfoWinner,
        ChallengeResult memory result,
        address challenger,
        uint256 challengeIdentNum
    ) internal returns (uint256 unFreezeAmount) {
        unFreezeAmount = challengeInfo.freezeAmount0 + challengeInfo.freezeAmount1 + MIN_CHALLENGE_DEPOSIT_AMOUNT;
        if (result.winner == challenger) {
            uint256 challengeUserAmount = (challengeInfo.freezeAmount0 * challengeInfo.challengeUserRatio) /
                ConstantsLib.RATIO_MULTIPLE;
            require(challengeUserAmount <= challengeInfo.freezeAmount0, "UAOF");

            uint256 challengerAmount = unFreezeAmount - challengeUserAmount;
            _challengeNodeList[challengeIdentNum].challengeFinished = true;

            // TODO: Not compatible with starknet network
            address user = address(uint160(challengeInfo.sourceTxFrom));
            IERC20 token = IERC20(challengeInfo.freezeToken);

            if (challengeInfo.freezeToken == address(0)) {
                (bool sent1, ) = payable(user).call{value: challengeUserAmount}("");
                require(sent1, "ETH: SE1");

                (bool sent2, ) = payable(result.winner).call{
                    value: (challengerAmount +
                        ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT +
                        challengeInfo.challengerVerifyTransactionFee)
                }("");
                require(sent2, "ETH: SE2");
            } else {
                token.safeTransfer(user, challengeUserAmount);
                token.safeTransfer(result.winner, challengerAmount);

                (bool sent3, ) = payable(result.winner).call{
                    value: ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT +
                        challengeInfo.challengerVerifyTransactionFee +
                        challengeInfo.freezeAmount0
                }("");
                require(sent3, "ETH: SE3");
            }
        } else if (_compareChallengerStatementHash(challengeInfo, challengeInfoWinner) == true) {
            (bool sent4, ) = payable(challenger).call{
                value: ConstantsLib.MIN_CHALLENGE_DEPOSIT_AMOUNT +
                    challengeInfo.challengerVerifyTransactionFee +
                    challengeInfo.freezeAmount0
            }("");
            require(sent4, "ETH: SE4");
        }
    }

    function _compareChallengerStatementHash(
        ChallengeStatement memory challengeInfo,
        ChallengeStatement memory winner
    ) internal pure returns (bool) {
        return (challengeInfo.sourceTxFrom == winner.sourceTxFrom &&
            challengeInfo.sourceTxTime == winner.sourceTxTime &&
            challengeInfo.freezeToken == winner.freezeToken &&
            challengeInfo.challengeUserRatio == winner.challengeUserRatio &&
            challengeInfo.freezeAmount0 == winner.freezeAmount0);
    }
}
