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

    uint256 public pointsSignerPK =
        uint256(
            0xA123
        ); // 模拟签名地址后端私钥

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

        // address predicted = factory.predictMarketAddress(0, salt);
        // console.log("Predicted market address:", predicted);

        address market = factory.createFutureMarket(
            0, // marketType
            salt,
            unicode"赌大小第1期",
            "DS1",
            packedTime
        );

        game = FutureMarketContract(payable(market));
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

        uint256 amount = 300;
        uint256 deadline = block.timestamp + 1 hours;

        // ALICE 下 A 方向
        bytes32 hash = game.hashTypedDataV4(
            ALICE,
            uint8(1),
            amount,
            game.nonces(ALICE),
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pointsSignerPK, hash);

        vm.prank(ALICE);
        game.betWithSignature(1, amount, deadline, v, r, s);

        (uint256 betAmounts, FutureMarketCommonStorage.Answer side) = game
            .getUserBet(ALICE);
        assertEq(betAmounts, 300);
        assertEq(uint256(side), 1); // A = 1
        assertEq(game.totalBetA(), 300);

        // ====================== BOB 测试单边限制 ======================

        vm.startPrank(BOB);

        // BOB 首次下 B 方向（成功）
        console.log("BOB first bet B side");
        hash = game.hashTypedDataV4(
            BOB,
            uint8(2),
            200,
            game.nonces(BOB),
            deadline
        );
        (v, r, s) = vm.sign(pointsSignerPK, hash);
        game.betWithSignature(2, 200, deadline, v, r, s);

        (betAmounts, side) = game.getUserBet(BOB);
        assertEq(betAmounts, 200);
        assertEq(uint256(side), 2); // B = 2

        // BOB 尝试下 A 方向 → 预期 revert
        console.log("BOB try add A side - should revert");
        hash = game.hashTypedDataV4(
            BOB,
            uint8(1),
            200,
            game.nonces(BOB),
            deadline
        );
        (v, r, s) = vm.sign(pointsSignerPK, hash);

        vm.expectRevert("Cannot bet on both sides"); // ← 必须在调用之前！
        game.betWithSignature(1, 200, deadline, v, r, s);

        // 如果上面没 revert，这里不会执行（测试失败）

        // BOB 可以继续加注 B 方向（成功）
        console.log("BOB can add more on B side");
        hash = game.hashTypedDataV4(
            BOB,
            uint8(2),
            300,
            game.nonces(BOB),
            deadline
        );
        (v, r, s) = vm.sign(pointsSignerPK, hash);
        game.betWithSignature(2, 300, deadline, v, r, s);

        (betAmounts, side) = game.getUserBet(BOB);
        assertEq(betAmounts, 500); // 200 + 300
        assertEq(uint256(side), 2);

        vm.stopPrank();
    }

    // // ==================== 测试开奖 + 领奖 ====================

    function testGameResolveAndClaim() public {
        _createGame(ALICE);

        // ALICE 全下 A 方向 500
        _signAndBet(ALICE, 1, 500);

        // BOB 全下 B 方向 700
        _signAndBet(BOB, 2, 700);

        vm.warp(REVEAL + 1);

        // 委员会开奖：B 赢，单积分收益 1.8（即 1 积分得 1.8 积分奖励）
        uint256 rewardPerPoint = 1.8 ether; // 1.8e18
        vm.startPrank(COMMITTEE);
        game.resolve(2, rewardPerPoint); // B 赢

        // 检查待领奖励
        assertEq(game.getPendingReward(ALICE), 0); // A 输 = 0
        assertEq(game.getPendingReward(BOB), 700 * 1.8 ether); // 700 * 1.8 = 1260

        vm.stopPrank();

        // BOB 领奖
        vm.startPrank(BOB);

        game.claim();

        // 再次查询应为 0
        assertEq(game.getPendingReward(BOB), 0);

        vm.stopPrank();

        // 不能重复领
        vm.startPrank(BOB);
        vm.expectRevert("Already claimed");
        game.claim();

        vm.stopPrank();

        // ALICE 无奖励
        vm.startPrank(ALICE);

        vm.expectRevert("Not winner"); // 或 "No winning bet"，取决于您的 claim 检查顺序
        game.claim();
        vm.stopPrank();
    }

    // ==================== 测试委员会更换 ====================

    function testChangeCommittee() public {
        _createGame(ALICE);

        address newCommittee = address(0x1);

        // 工厂设置只影响新市场
        vm.startPrank(OWNER);
        factory.setInitialCommittee(newCommittee);

        // 当前市场仍为旧 committee
        assertEq(game.getCommittee(), COMMITTEE);
        vm.stopPrank();

        // owner 可直接在市场合约修改
        vm.startPrank(POINTS_SIGNER);

        game.setCommittee(newCommittee);

        assertEq(game.getCommittee(), newCommittee);
        vm.stopPrank();
    }

    // // ==================== 内部工具函数 ====================

    function _createGame(address user) internal {
        vm.startPrank(user);

        bytes32 salt = _salt(user, 1);
        // address payable predicted = payable(
        //     factory.predictMarketAddress(0, salt)
        // );

        address payable predicted = payable(
            factory.createFutureMarket(0, salt, "Test Game", "TG", packedTime)
        );

        game = (FutureMarketContract(predicted));
        console.log("game:", address(game));
        console.log("pointsSigner:", game.getPointsSigner());
        vm.warp(START + 10);
        vm.stopPrank();
    }
    function _signAndBet(
        address user,
        uint8 answerRaw,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = game.hashTypedDataV4(
            user,
            answerRaw,
            amount,
            game.nonces(user),
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pointsSignerPK, hash);

        game.betWithSignature(answerRaw, amount, deadline, v, r, s);
        vm.stopPrank();
    }

    function _salt(address user, uint96 index) internal view returns (bytes32) {
        return factory.salt(user, index);
    }
}
