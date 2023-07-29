// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

library RuleLib {
    struct Rule {
        uint64 chainId0; // 59144
        uint64 chainId1; // 10
        uint8 status0;
        uint8 status1;
        uint token0;
        uint token1;
        uint128 minPrice0;
        uint128 minPrice1;
        uint128 maxPrice0;
        uint128 maxPrice1;
        uint128 withholdingFee0;
        uint128 withholdingFee1;
        uint16 tradingFee0;
        uint16 tradingFee1;
        uint32 responseTime0;
        uint32 responseTime1;
        uint32 compensationRatio0;
        uint32 compensationRatio1;
        uint64 enableTimestamp;
    }

    struct RootWithVersion {
        bytes32 root;
        uint32 version;
    }
}
