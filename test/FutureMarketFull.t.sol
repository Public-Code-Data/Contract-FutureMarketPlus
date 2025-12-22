// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol";
import "../src/contract/FutureMarketCommonStorage.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract FutureMarketFullTest is Test {
    FutureMarketFactoryContract public factory;
    FutureMarketContract public implementationV1;
    FutureMarketContract public game;

    uint256 public constant AMOUNTS = 1 * 10 ** 6;

    ERC20Mock public usdt;

    address constant OWNER = address(0x1);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant COMMITTEE = 0xC565FC29F6df239Fe3848dB82656F2502286E97d;

    uint256 constant START = 1000;
    uint256 constant END = 2000;
    uint256 constant REVEAL = 3000;

    function setUp() public {
        vm.startBroadcast(OWNER);

        // 1. 部署普通实现
        implementationV1 = new FutureMarketContract();

        // 2. 部署 UUPS 工厂代理
        address proxy = Upgrades.deployUUPSProxy(
            "FutureMarketFactoryContract.sol",
            abi.encodeCall(
                FutureMarketFactoryContract.initialize,
                (address(implementationV1))
            )
        );
        factory = FutureMarketFactoryContract(proxy);

        assertEq(factory.implementationTypes(0), address(implementationV1));

        _createUSDT();
        vm.stopBroadcast();
    }

    function testFactoryCreateCollection() public {
        vm.startBroadcast(ALICE);

        bytes memory packed = abi.encode(
            uint32(START),
            uint32(END),
            uint32(REVEAL)
        );
        bytes32 collectionId = _salt(ALICE, 1);

        factory.createFutureMarketCollection(
            collectionId,
            0,
            unicode"赌大小",
            unicode"DS",
            packed
        );

        address predicted = factory.predictDeterministicAddress(
            collectionId,
            0
        );
        assertEq(factory.ownerOf(uint256(uint160(predicted))), ALICE);

        game = FutureMarketContract(payable(predicted));

        assertEq(game.startTime(), uint32(START));
        assertEq(game.endTime(), uint32(END));
        assertEq(game.resolutionTime(), uint32(REVEAL));

        assertEq(game.marketName(), unicode"赌大小");
        assertEq(game.marketSymbol(), unicode"DS");
        console.log("name:", game.marketName());
        console.log("symbol:", game.marketSymbol());

        vm.stopBroadcast();
    }

    function testGameBet() public {
        _createGame(ALICE);

        vm.startBroadcast(ALICE);
        usdt.approve(address(game), AMOUNTS);
        game.buy(AMOUNTS, FutureMarketCommonStorage.Answer.A);
        vm.stopBroadcast();

        assertTrue(game.userBetStatus(ALICE));
        assertEq(
            uint(game.userAnswer(ALICE)),
            uint(FutureMarketCommonStorage.Answer.A)
        );
    }

    function testGameRevealAndClaim() public {
        _createGame(ALICE);

        // Alice 买 A
        console.log("ALICE buy A");

        vm.startBroadcast(ALICE);
        usdt.approve(address(game), AMOUNTS);
        game.buy(AMOUNTS, FutureMarketCommonStorage.Answer.A);
        vm.stopBroadcast();

        // Bob 买 B
        console.log("BOB buy A");

        vm.startBroadcast(BOB);
        usdt.mint(BOB, 1000e6);
        usdt.approve(address(game), AMOUNTS);
        game.buy(AMOUNTS, FutureMarketCommonStorage.Answer.B);
        vm.stopBroadcast();

        // 时间到开奖
        vm.warp(REVEAL + 1);

        // 委员会公布 B 赢
        console.log("COMMITTEE resolutionAnswer Answer B");
        vm.startBroadcast(COMMITTEE);
        game.resolutionAnswer(FutureMarketCommonStorage.Answer.B, 100, 1);
        vm.stopBroadcast();

        // 关键修复2：getPointsReward 是 view function，需要传 msg.sender
        vm.startBroadcast(ALICE);
        assertEq(game.getPointsReward(), 1);
        vm.stopBroadcast();

        vm.startBroadcast(BOB);
        assertEq(game.getPointsReward(), 100);
        vm.stopBroadcast();
    }

    // ===================== 内部工具函数 =====================

    function _createGame(address user) internal {
        vm.startBroadcast(user);

        usdt.mint(user, 1000e6);

        bytes memory packed = abi.encode(
            uint32(START),
            uint32(END),
            uint32(REVEAL)
        );
        bytes32 collectionId = _salt(user, 1);

        factory.createFutureMarketCollection(
            collectionId,
            0,
            unicode"赌大小第1期",
            unicode"DS1",
            packed
        );

        address addr = factory.predictDeterministicAddress(collectionId, 0);
        game = FutureMarketContract(payable(addr));

        vm.warp(START + 10);
        vm.stopBroadcast();

        // 设置 USDT
        vm.startBroadcast(COMMITTEE);
        game.setPayToken(address(usdt));
        game.setPrizePoolAddress(COMMITTEE);
        vm.stopBroadcast();
    }

    function _salt(address user, uint96 index) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 96) | index);
    }

    function _createUSDT() internal {
        usdt = new ERC20Mock();
        usdt.mint(ALICE, 10000e6);
        usdt.mint(BOB, 10000e6);
    }
}
