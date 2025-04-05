// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Coin} from "../src/Coin.sol";
import {WowFactoryImpl} from "../src/WowFactoryImpl.sol";

contract DeployScript is Script {
    // Anvil 测试网络配置
    address public constant WETH = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // 我们将在部署时创建的WETH地址
    address public constant UNISWAP_V3_POSITION_MANAGER = address(1); // 模拟地址
    address public constant UNISWAP_V3_ROUTER = address(2); // 模拟地址

    function setUp() public {
        // 如果需要，可以在这里进行一些设置
    }

    function run() external {
        // 使用 anvil 的默认私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 Coin 实现合约
        address protocolFeeRecipient = deployer;
        address protocolRewards = deployer;

        Coin coinImpl = new Coin(
            protocolFeeRecipient,
            protocolRewards,
            WETH,
            UNISWAP_V3_POSITION_MANAGER,
            UNISWAP_V3_ROUTER
        );
        console2.log("Coin implementation deployed at:", address(coinImpl));

        // 2. 部署 WowFactoryImpl 实现合约
        WowFactoryImpl factoryImpl = new WowFactoryImpl(address(coinImpl));
        console2.log("WowFactoryImpl implementation deployed at:", address(factoryImpl));

        // 3. 准备初始化数据
        bytes memory initData = abi.encodeCall(WowFactoryImpl.initialize, (deployer));

        // 4. 部署代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(factoryImpl),
            initData
        );
        console2.log("WowFactory proxy deployed at:", address(proxy));

        // 5. 验证部署
        WowFactoryImpl factory = WowFactoryImpl(address(proxy));
        console2.log("Implementation address (through proxy):", factory.implementation());

        vm.stopBroadcast();

        // 打印部署总结
        console2.log("\n=== Deployment Summary ===");
        console2.log("Coin Implementation:", address(coinImpl));
        console2.log("WowFactory Implementation:", address(factoryImpl));
        console2.log("WowFactory Proxy:", address(proxy));
    }
}