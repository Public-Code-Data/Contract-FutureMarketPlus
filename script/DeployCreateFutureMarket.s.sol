// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../src/FutureMarketFactoryContract.sol";
import "../src/contract/FutureMarketContract.sol"; // 当前可升级的 Layout 风格实现合约

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployCreateFutureMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);
        //部署的工厂合约
        FutureMarketFactoryContract factory = FutureMarketFactoryContract(address(0x1C50eCF7567bc75dDc07DC59F1671008266BfDf9));
        bytes32 salt = factory.salt(deployer, 1);

        uint32 startTime = 1000;
        uint32 endTime = 2000;
        uint32 revel = 3000;
        bytes memory packedTime = abi.encode(uint32(startTime), uint32(endTime = 2000), uint32(revel));

        address market = factory.createFutureMarket(
            0, // marketType
            salt,
            unicode"赌大小第1期",
            "DS1",
            packedTime
        );
        console.log("new market:", market);

        FutureMarketContract game = FutureMarketContract(payable(market));
        console.log("getCommittee =", game.getCommittee());
        console.log("getPointsSigner =", game.getPointsSigner());

        console.log("startTime =", game.startTime());
        console.log("endTime =", game.endTime());
        console.log("resolutionTime =", game.resolutionTime());

        (string memory name, string memory symbol, , , , , , , , , ) = game
            .getMarketInfo();
        console.log("name =", name);
        console.log("symbol =", symbol);

        vm.stopBroadcast();
    }
}
