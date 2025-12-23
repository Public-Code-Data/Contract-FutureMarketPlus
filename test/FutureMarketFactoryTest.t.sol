// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol";
import "../src/contract/FutureMarketContractV2.sol"; // V2 用于升级测试

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FutureMarketFactoryTest is Test {
    FutureMarketFactoryContract public factory;
    FutureMarketContract public implV1;
    FutureMarketContractV2 public implV2;

    address constant OWNER = address(0x1);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant COMMITTEE = address(0xC565FC29F6df239Fe3848dB82656F2502286E97d);
    address constant POINTS_SIGNER = address(0xC565FC29F6df239Fe3848dB82656F2502286E97d);

    bytes constant packedTime = abi.encode(uint32(1000), uint32(2000), uint32(3000));

    event MarketCreated(
        address indexed market,
        address indexed owner,
        uint256 indexed tokenId,
        uint256 marketType,
        string name,
        string symbol
    );

    function setUp() public {
        vm.startPrank(OWNER);

        // 部署 V1 实现
        implV1 = new FutureMarketContract();

        // 部署工厂代理并初始化
        address proxy = Upgrades.deployUUPSProxy(
            "FutureMarketFactoryContract.sol",
            abi.encodeCall(
                FutureMarketFactoryContract.initialize,
                (address(implV1), POINTS_SIGNER, COMMITTEE)
            )
        );
        factory = FutureMarketFactoryContract(proxy);

        console.log("Factory deployed at:", address(factory));
        console.log("Beacon (type 0):", factory.getBeacon(0));
        console.log("Implementation V1:", factory.getImplementation(0));

        vm.stopPrank();
    }

    // ==================== 创建市场 + 防抢注 ====================

    function testCreateMarketAndAntiFrontRunning() public {
        bytes32 validSalt = _salt(ALICE, 1);
        bytes32 invalidSalt = _salt(BOB, 1); // 前20字节是 BOB

        // 无效 salt → revert
        vm.startPrank(ALICE);
        vm.expectRevert("Invalid caller");
        factory.createFutureMarket(0, invalidSalt, "Invalid", "INV", packedTime);
        vm.stopPrank();

        // 有效 salt → 成功
        vm.startPrank(ALICE);
        vm.recordLogs();
        factory.createFutureMarket(0, validSalt, unicode"Alice的盘口", "ALICE", packedTime);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        address market = _getMarketFromLogs(entries);

        assertEq(factory.ownerOf(uint256(uint160(market))), ALICE);

        FutureMarketContract game = FutureMarketContract(payable(market));
        assertEq(game.getCommittee(), COMMITTEE);
        assertEq(game.startTime(), 1000);
        assertEq(game.endTime(), 2000);
        assertEq(game.resolutionTime(), 3000);
        assertEq(game.marketName(), unicode"Alice的盘口");
        assertEq(game.marketSymbol(), "ALICE");

        vm.stopPrank();
    }

    // ==================== 批量升级 ====================

    function testBatchUpgrade() public {
        // 创建两个市场
        address  market1 = _createMarket(ALICE, 1, "Market1", "M1");
        address market2 = _createMarket(BOB, 1, "Market2", "M2");

        FutureMarketContract game1 = FutureMarketContract(payable(market1));
        FutureMarketContract game2 = FutureMarketContract(payable(market2));

        // 初始应为 V1（如果 V1 有 getVersion，返回 "v1"）
        // 这里我们用 V2 的 getVersion 验证升级

        // 部署 V2 实现
        vm.startPrank(OWNER);
        implV2 = new FutureMarketContractV2();
        factory.upgradeMarketType(0, address(implV2));
        vm.stopPrank();

        // 升级后两个市场都应返回 "v2"
        assertEq(FutureMarketContractV2(payable(market1)).getVersion(), "v2");
        assertEq(FutureMarketContractV2(payable(market2)).getVersion(), "v2");

        // 原有数据保留（简单验证初始化数据）
        assertEq(game1.getCommittee(), COMMITTEE);
        assertEq(game2.getCommittee(), COMMITTEE);
    }

    // ==================== 多市场类型 ====================

    function testMultiMarketType() public {
        // 添加新类型 1（使用 V2 实现作为示例）
        vm.startPrank(OWNER);
        implV2 = new FutureMarketContractV2();
        factory.addMarketType(1, address(implV2));
        vm.stopPrank();

        // 创建 type 0 市场（V1）
        address type0Market = _createMarket(ALICE, 1, "Type0", "T0");
        // FutureMarketContract type0 = FutureMarketContract(payable(type0Market));

        // 创建 type 1 市场（V2）
        address type1Market = _createMarket(BOB, 2, "Type1", "T1", 1);
        FutureMarketContractV2 type1 = FutureMarketContractV2(payable(type1Market));

        // 初始版本验证
        // type0 是 V1，type1 是 V2
        assertEq(type1.getVersion(), "v2");

        // 升级 type 0 到 V2
        vm.startPrank(OWNER);
        factory.upgradeMarketType(0, address(implV2));
        vm.stopPrank();

        // type0 升级成功，type1 不受影响（仍是 V2）
        assertEq(FutureMarketContractV2(payable(type0Market)).getVersion(), "v2");
        assertEq(type1.getVersion(), "v2");
    }

    // ==================== 配置函数 ====================

    function testConfigFunctions() public {
        address newSigner = address(0x1);
        address newCommittee = address(0x2);

        vm.startPrank(OWNER);
        factory.setPointsSigner(newSigner);
        factory.setInitialCommittee(newCommittee);
        vm.stopPrank();

        assertEq(factory.pointsSigner(), newSigner);
        assertEq(factory.initialCommittee(), newCommittee);

        // 新市场使用新 committee
        address newMarket = _createMarket(ALICE, 3, "NewConfig", "NC");
        FutureMarketContract game = FutureMarketContract(payable(newMarket));
        assertEq(game.getCommittee(), newCommittee);
    }

    // ==================== burnOwnership ====================

    function testBurnOwnership() public {
        address market = _createMarket(ALICE, 1, "Burnable", "BURN");
        uint256 tokenId = uint256(uint160(market));

        assertEq(factory.ownerOf(tokenId), ALICE);

        vm.startPrank(ALICE);
        factory.burnOwnership(tokenId);
        vm.stopPrank();

        vm.expectRevert();
        factory.ownerOf(tokenId);
    }

    // ==================== 内部工具函数 ====================

    function _salt(address user, uint96 index) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 96) | index);
    }

    function _createMarket(
        address user,
        uint96 index,
        string memory name,
        string memory symbol
    ) internal returns (address market) {
        return _createMarket(user, index, name, symbol, 0);
    }

    function _createMarket(
        address user,
        uint96 index,
        string memory name,
        string memory symbol,
        uint256 marketType
    ) internal returns (address market) {
        vm.startPrank(user);

        bytes32 salt = _salt(user, index);

        vm.recordLogs();
        factory.createFutureMarket(marketType, salt, name, symbol, packedTime);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        market = _getMarketFromLogs(entries);
        require(market != address(0), "Market not created");

        vm.stopPrank();
    }

    function _getMarketFromLogs(Vm.Log[] memory entries) internal pure returns (address market) {
        bytes32 eventSig = keccak256("MarketCreated(address,address,uint256,uint256,string,string)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSig) {
                // topics[1] 是 indexed market
                market = address(uint160(uint256(entries[i].topics[1])));
                return market;
            }
        }
        revert("MarketCreated event not found");
    }
}