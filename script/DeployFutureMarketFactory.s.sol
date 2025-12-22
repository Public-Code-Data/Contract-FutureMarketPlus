// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FutureMarketFactoryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // ==================== Step 1: 部署普通实现合约（关键！） ====================
        FutureMarketContract marketImpl = new FutureMarketContract();
        console.log("FutureMarketContract Implementation deployed at:", address(marketImpl));

        // ==================== Step 2: 部署工厂 UUPS 代理（不变） ====================
        address factoryProxy = Upgrades.deployUUPSProxy(
            "FutureMarketFactoryContract.sol",
            abi.encodeCall(FutureMarketFactoryContract.initialize, (address(marketImpl))) // 传实现地址
        );

        address factoryImpl = Upgrades.getImplementationAddress(factoryProxy);
        console.log("FutureMarketFactory Proxy:", factoryProxy);
        console.log("FutureMarketFactory Implementation:", factoryImpl);

        // ==================== Step 3: 设置 implementationTypes[0] ====================
        FutureMarketFactoryContract factory = FutureMarketFactoryContract(factoryProxy);
        factory.setImplementationAddress(0, address(marketImpl));
        console.log("setImplementationAddress(0) =>", address(marketImpl));

        // ==================== Step 4: 打印预测地址（前端必备） ====================
        bytes32 saltExample = keccak256(abi.encodePacked(vm.addr(deployerPrivateKey))); // 示例 salt
        address predicted = factory.predictDeterministicAddress(saltExample, 0);
        console.log("Example Predicted Collection Address (for current deployer):");
        console.logAddress(predicted);

        console.log("");
        console.log("1. factoryProxy:", factoryProxy);
        console.log("2. marketImpl:", address(marketImpl));

        vm.stopBroadcast();
    }
}
