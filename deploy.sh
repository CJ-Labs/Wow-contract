# 编译合约
forge build

# 使用环境变量中的 RPC_URL 运行部署脚本
forge script script/DeployScript.s.sol:DeployScript --fork-url $RPC_URL --broadcast -vvvv

# 如果要在其他网络部署，替换 --fork-url 参数即可
# 例如在 Sepolia 测试网：
# forge script script/DeployScript.s.sol:DeployScript --fork-url $RPC_URL --broadcast -vvvv

地址: 0x9dfe2189745625249b28c72edd71f72b8a57a0a7
作用: 这是代币合约的实现合约，包含了所有代币相关的核心逻辑，如铸造、销毁、转账等功能。

地址: 0xc8d37e8b30ceab4f267e26d402fc5dfd6130bad4
作用: 这是工厂合约的实现合约，负责创建和管理新的代币合约实例。

地址: 0x0f6e9b29bd1bdae2b442e314366e5c10088e541f
作用: 这是最终用户会实际交互的合约地址。它是一个代理合约，将调用转发到 WowFactoryImpl 实现合约。使用代理模式可以在将来升级合约逻辑。
