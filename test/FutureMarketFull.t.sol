// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol"; // 当前 Layout 风格的可升级实现
import "../src/contract/FutureMarketCommonStorage.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FutureMarketFullTest is Test {
    using FutureMarketCommonStorage for FutureMarketCommonStorage.Layout;

    FutureMarketFactoryContract public factory;
    FutureMarketContract public implementationV1;
    FutureMarketContract public game;

    uint256 public constant BET_UNIT = 100; // 100 积分单位

    address constant OWNER = address(0x1);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant COMMITTEE =
        address(0xC565FC29F6df239Fe3848dB82656F2502286E97d); // 可变委员会
    address constant POINTS_SIGNER =
        address(0xC565FC29F6df239Fe3848dB82656F2502286E97d); // 后端签名私钥地址

    uint256 public pointsSignerPK = uint256(0x1234); // 模拟后端私钥

    uint32 constant START = 1000;
    uint32 constant END = 2000;
    uint32 constant REVEAL = 3000;

    bytes packedTime;

    function setUp() public {
        // 打包时间数据（96 bytes）
        packedTime = abi.encode(uint32(START), uint32(END), uint32(REVEAL));

        vm.startPrank(OWNER);

        // 1. 部署 FutureMarketContract 实现合约（v1）
        implementationV1 = new FutureMarketContract();

        // 2. 部署工厂代理（Beacon 模式）
        address proxy = Upgrades.deployUUPSProxy(
            "FutureMarketFactoryContract.sol",
            abi.encodeCall(
                FutureMarketFactoryContract.initialize,
                (address(implementationV1), POINTS_SIGNER, COMMITTEE)
            )
        );
        factory = FutureMarketFactoryContract(proxy);

        console.log("Factory deployed at:", address(factory));
        console.log("Beacon (type 0):", factory.getBeacon(0));
        console.log("Implementation:", factory.getImplementation(0));

        vm.stopPrank();
    }

    // ==================== 测试创建市场 ====================

    function testFactoryCreateMarket() public {
        vm.startPrank(ALICE);

        bytes32 salt = _salt(ALICE, 1);

        address predicted = factory.predictMarketAddress(0, salt);
        console.log("Predicted market address:", predicted);

        factory.createFutureMarket(
            0, // marketType
            salt,
            unicode"赌大小第1期",
            "DS1",
            packedTime
        );

        assertEq(factory.ownerOf(uint256(uint160(predicted))), ALICE);

        game = FutureMarketContract(payable(predicted));
        console.log("1---:");
        console.log(game.getCommittee());
        console.log(game.startTime());
        console.log(game.endTime());
        console.log(game.resolutionTime());
            
        assertEq(game.getCommittee(), COMMITTEE);
        assertEq(game.startTime(), START);
        assertEq(game.endTime(), END);
        assertEq(game.resolutionTime(), REVEAL);
        console.log("2---:");

        (string memory name, string memory symbol, , , , , , , , , ) = game
            .getMarketInfo();
        assertEq(name, unicode"赌大小第1期");
        assertEq(symbol, "DS1");

        vm.warp(START + 10); // 进入下注阶段
        vm.stopPrank();
    }

    // ==================== 测试签名下注 ====================

    function testGameBetWithSignature() public {
        _createGame(ALICE);

        uint256 amount = 300; // 3 × 100 积分
        uint256 deadline = block.timestamp + 1 hours;

        // 模拟后端签名（A 方向）
        bytes32 structHash = keccak256(
            abi.encode(
                game.BET_TYPEHASH(),
                ALICE,
                uint8(1), // 1 = A
                amount,
                game.nonces(ALICE),
                deadline
            )
        );
        bytes32 hash = game.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pointsSignerPK, hash);

        // 任何人可提交（这里用 BOB 提交）
        vm.prank(BOB);
        game.betWithSignature(ALICE, 1, amount, deadline, v, r, s);

        (uint256 betA, uint256 betB) = game.getUserBet(ALICE);
        assertEq(betA, 300);
        assertEq(betB, 0);
        assertEq(game.totalBetA(), 300);

        // 再次下注 B 方向
        structHash = keccak256(
            abi.encode(
                game.BET_TYPEHASH(),
                ALICE,
                uint8(2), // 2 = B
                200,
                game.nonces(ALICE),
                deadline
            )
        );
        hash = game.hashTypedDataV4(structHash);
        (v, r, s) = vm.sign(pointsSignerPK, hash);

        vm.prank(BOB);
        game.betWithSignature(ALICE, 2, 200, deadline, v, r, s);

        (betA, betB) = game.getUserBet(ALICE);
        assertEq(betA, 300);
        assertEq(betB, 200);
    }

    // ==================== 测试开奖 + 领奖 ====================

    function testGameResolveAndClaim() public {
        _createGame(ALICE);

        // Alice 下 300 A, 200 B
        _signAndBet(ALICE, 1, 300);
        _signAndBet(ALICE, 2, 200);

        // Bob 下 400 A
        _signAndBet(BOB, 1, 400);

        vm.warp(REVEAL + 1);

        // 委员会开奖：B 赢，单积分收益 1.8（即 1 积分得 1.8 积分奖励）
        uint256 rewardPerPoint = 1.8 ether; // 1.8e18

        vm.prank(COMMITTEE);
        game.resolve(2, rewardPerPoint); // B 赢

        // 检查待领奖励
        assertEq(game.getPendingReward(ALICE), 200 * 1.8 ether); // 200 * 1.8 = 360
        assertEq(game.getPendingReward(BOB), 0); // Bob 猜错

        // Alice 领奖
        vm.prank(ALICE);
        game.claim();

        // 再次查询应为 0
        assertEq(game.getPendingReward(ALICE), 0);

        // 不能重复领
        vm.prank(ALICE);
        vm.expectRevert("Already claimed");
        game.claim();
    }

    // ==================== 测试委员会更换 ====================

    function testChangeCommittee() public {
        _createGame(ALICE);

        address newCommittee = address(
            0xC565FC29F6df239Fe3848dB82656F2502286E97d
        );

        vm.prank(OWNER);
        factory.setInitialCommittee(newCommittee); // 只影响后续市场

        // 当前市场仍为旧 committee
        assertEq(game.getCommittee(), COMMITTEE);

        // owner 可在单个市场内修改
        vm.prank(OWNER);
        game.setCommittee(newCommittee);

        assertEq(game.getCommittee(), newCommittee);
    }

    // ==================== 内部工具函数 ====================

    function _createGame(address user) internal {
        vm.startPrank(user);

        bytes32 salt = _salt(user, 1);
        address payable predicted = payable(
            factory.predictMarketAddress(0, salt)
        );

        factory.createFutureMarket(0, salt, "Test Game", "TG", packedTime);

        game = FutureMarketContract(predicted);

        vm.warp(START + 10);
        vm.stopPrank();
    }

    function _signAndBet(
        address user,
        uint8 answerRaw,
        uint256 amount
    ) internal {
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                game.BET_TYPEHASH(),
                user,
                answerRaw,
                amount,
                game.nonces(user),
                deadline
            )
        );
        bytes32 hash = game.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pointsSignerPK, hash);

        vm.prank(user); // 模拟用户提交
        game.betWithSignature(user, answerRaw, amount, deadline, v, r, s);
    }

    function _salt(address user, uint96 index) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 96) | index);
    }
}
