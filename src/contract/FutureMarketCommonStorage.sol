// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library FutureMarketCommonStorage {
    struct Layout {
        // 基本信息
        string marketName;
        string marketSymbol;
        uint32 startTime;
        uint32 endTime;
        uint32 resolutionTime;

        // 开奖状态
        bool resolved;
        Answer winningAnswer;        // A 或 B
        uint256 rewardPerPoint;      // 单积分收益（18 位小数）

        // 下注记录（积分单位）
        mapping(address => uint256) betA;
        mapping(address => uint256) betB;
        uint256 totalA;
        uint256 totalB;

        // 领奖记录
        mapping(address => uint256) claimedReward;

        // 权限与配置
        address factory;
        address pointsSigner;        // 后端签名者
        address committee;           // 可变委员会地址

        // 防重放
        mapping(address => uint256) nonces;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("futuremarket.storage.v1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    enum Answer {
        Empty,
        A,
        B
    }
}