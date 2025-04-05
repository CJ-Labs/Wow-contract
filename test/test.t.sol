// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockNonfungiblePositionManager} from "../mock/MockNonfungiblePositionManager.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {WETH} from "@solmate-token/WETH.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MockProtocolRewards} from "../mock/MockProtocolRewards.sol";
import {MockSwapRouter} from "../mock/MockSwapRouter.sol";
import {MockUniswapV3Pool} from "../mock/MockUniswapV3Pool.sol";
import {WowFactoryImpl} from "../src/WowFactoryImpl.sol";
import {Coin} from "../src/Coin.sol";

contract WowTest is Test {
    // 合约实例
    WETH public weth;
    Coin public coinImpl;
    WowFactoryImpl public factoryImpl;
    WowFactoryImpl public factory;

    // Mock 合约实例
    MockProtocolRewards public protocolRewards;
    MockNonfungiblePositionManager public positionManager;
    MockSwapRouter public swapRouter;
    MockUniswapV3Pool public uniswapPool;

    // 测试账户
    address public deployer;
    address public user1;
    address public user2;

    function setUp() public {
        // 设置测试账户
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 给测试账户一些 ETH
        vm.deal(deployer, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(deployer);

        // 部署 Mock 合约
        weth = new WETH();
        protocolRewards = new MockProtocolRewards();
        positionManager = new MockNonfungiblePositionManager();
        swapRouter = new MockSwapRouter();
        uniswapPool = MockUniswapV3Pool(positionManager.mockPool());

        console2.log("Mock contracts deployed:");
        console2.log("- WETH:", address(weth));
        console2.log("- ProtocolRewards:", address(protocolRewards));
        console2.log("- PositionManager:", address(positionManager));
        console2.log("- SwapRouter:", address(swapRouter));
        console2.log("- UniswapPool:", address(uniswapPool));

        // 部署 Coin 实现合约
        coinImpl = new Coin(
            deployer, // protocolFeeRecipient
            address(protocolRewards),
            address(weth),
            address(positionManager),
            address(swapRouter)
        );
        console2.log("Coin implementation deployed at:", address(coinImpl));

        // 部署 WowFactoryImpl
        factoryImpl = new WowFactoryImpl(address(coinImpl));
        console2.log("WowFactoryImpl deployed at:", address(factoryImpl));

        // 部署并初始化代理合约
        bytes memory initData = abi.encodeCall(WowFactoryImpl.initialize, (deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(factoryImpl),
            initData
        );
        factory = WowFactoryImpl(address(proxy));
        console2.log("WowFactory proxy deployed at:", address(factory));

        vm.stopPrank();
    }

    function test_InitialState() public {
        console2.log("Testing initial state...");
        assertEq(factory.owner(), deployer, "Owner should be deployer");
        assertEq(factory.coinImpl(), address(coinImpl), "Coin implementation address should match");
    }

    function test_DeployCoin() public {
        vm.startPrank(user1);
        console2.log("Deploying new coin from user1...");

        // 部署新的代币
        address coinAddress = factory.deploy(
            user1,           // creator
            user2,           // platformReferrer
            "testURI",      // tokenURI
            "TestCoin",     // name
            "TEST"          // symbol
        );
        console2.log("New coin deployed at:", coinAddress);

        // 验证代币部署成功
        assertTrue(coinAddress != address(0), "Coin address should not be zero");

        // 获取代币实例
        Coin coin = Coin(payable(coinAddress));

        // 验证代币基本信息
        assertEq(coin.name(), "TestCoin", "Coin name should match");
        assertEq(coin.symbol(), "TEST", "Coin symbol should match");
        assertEq(coin.tokenCreator(), user1, "Token creator should be user1");
        assertEq(coin.platformReferrer(), user2, "Platform referrer should be user2");

        vm.stopPrank();
    }

    function test_DeployCoin_WithETH() public {
        vm.startPrank(user1);
        uint256 deployAmount = 1 ether;
        console2.log("Deploying new coin with ETH amount:", deployAmount);

        // 部署新的代币并发送 ETH
        address coinAddress = factory.deploy{value: deployAmount}(
            user1,           // creator
            user2,           // platformReferrer
            "testURI",      // tokenURI
            "TestCoin",     // name
            "TEST"          // symbol
        );
        console2.log("New coin deployed at:", coinAddress);

        // 验证代币部署成功
        assertTrue(coinAddress != address(0), "Coin address should not be zero");

        // 获取代币实例
        Coin coin = Coin(payable(coinAddress));

        // 验证代币基本信息
        assertEq(coin.name(), "TestCoin", "Coin name should match");
        assertEq(coin.symbol(), "TEST", "Coin symbol should match");
        assertEq(coin.tokenCreator(), user1, "Token creator should be user1");
        assertEq(coin.platformReferrer(), user2, "Platform referrer should be user2");

        // 验证 WETH 余额
        assertGt(weth.balanceOf(user1), 0, "User1 should have received WETH");

        vm.stopPrank();
    }

    function test_RevertWhen_DeployingCoinWithZeroCreator() public {
        vm.startPrank(user1);
        console2.log("Testing deployment with zero creator address...");

        // 正确的错误期望方式
        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));

        factory.deploy(
            address(0),     // creator (zero address)
            user2,          // platformReferrer
            "testURI",      // tokenURI
            "TestCoin",     // name
            "TEST"          // symbol
        );

        vm.stopPrank();
    }

    // 在合约中定义错误
    error OwnableUnauthorizedAccount(address account);

    function test_RevertWhen_UpgradingFactoryByNonOwner() public {
        vm.startPrank(user1);
        console2.log("Testing upgrade by non-owner...");

        // 部署新版本的工厂实现
        WowFactoryImpl newFactoryImpl = new WowFactoryImpl(address(coinImpl));
        console2.log("New factory implementation deployed at:", address(newFactoryImpl));

        // 准备升级数据
        bytes memory initData = "";

        // 非所有者尝试升级，应该失败
        // 使用自定义错误
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                user1
            )
        );

        UUPSUpgradeable(address(factory)).upgradeToAndCall(
            address(newFactoryImpl),
            initData
        );

        vm.stopPrank();
    }

    function test_UpgradeFactory() public {
        vm.startPrank(deployer);
        console2.log("Testing factory upgrade by owner...");

        // 部署新版本的工厂实现
        WowFactoryImpl newFactoryImpl = new WowFactoryImpl(address(coinImpl));
        console2.log("New factory implementation deployed at:", address(newFactoryImpl));

        // 准备升级数据
        bytes memory initData = "";

        // 升级到新实现
        UUPSUpgradeable(address(factory)).upgradeToAndCall(
            address(newFactoryImpl),
            initData
        );

        // 验证升级成功
        assertEq(
            factory.implementation(),
            address(newFactoryImpl),
            "Implementation address should be updated"
        );

        vm.stopPrank();
    }

    // 接收 ETH 的回退函数
    receive() external payable {}
}