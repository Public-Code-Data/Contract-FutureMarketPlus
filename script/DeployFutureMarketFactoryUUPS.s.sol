// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol"; // 当前可升级的 Layout 风格实现合约

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployFutureMarketFactoryUUPS is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // ==================== Step 1: 部署 FutureMarketContract 实现合约（v1） ====================
        FutureMarketContract marketImpl = new FutureMarketContract();
        console.log("FutureMarketContract Implementation (v1) deployed at:", address(marketImpl));

        // ==================== Step 2: 配置必要地址（从环境变量或硬编码） ====================
        // 后端积分签名者私钥地址（必须安全保管！）
        address pointsSigner = vm.envAddress("POINTS_SIGNER_ADDRESS");
        console.log("Points Signer (backend):", pointsSigner);

        // 初始委员会地址（可后期修改）
        address initialCommittee = vm.envAddress("INITIAL_COMMITTEE_ADDRESS");
        console.log("Initial Committee Address:", initialCommittee);

        // ==================== Step 3: 部署工厂 UUPS 代理 + 初始化 ====================
        address factoryProxy = Upgrades.deployUUPSProxy(
            "FutureMarketFactoryContract.sol",
            abi.encodeCall(
                FutureMarketFactoryContract.initialize,
                (
                    address(marketImpl),     // 初始实现地址（用于默认 marketType 0 的 Beacon）
                    pointsSigner,            // 后端签名者
                    initialCommittee         // 初始委员会地址
                )
            )
        );

        FutureMarketFactoryContract factory = FutureMarketFactoryContract(factoryProxy);

        console.log("FutureMarketFactory Proxy deployed at:", factoryProxy);
        console.log("Factory Implementation:", Upgrades.getImplementationAddress(factoryProxy));

        // ==================== Step 4: 验证 Beacon 和 Implementation ====================
        address beacon0 = factory.getBeacon(0);
        address currentImpl = factory.getImplementation(0);

        console.log("Beacon (marketType 0):", beacon0);
        console.log("Current Implementation for type 0:", currentImpl);
        assert(currentImpl == address(marketImpl));

        
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Factory Proxy:", factoryProxy);
        console.log("FutureMarketContract Implementation (v1):", address(marketImpl));
        console.log("Points Signer:", pointsSigner);
        console.log("Initial Committee:", initialCommittee);
        console.log("");
        console.log("Next Step: Users can call createFutureMarket() with proper salt to create markets");
        console.log("Future Upgrades: Use upgradeMarketType(0, newImpl) to batch upgrade all type-0 markets");

        vm.stopBroadcast();
    }
}