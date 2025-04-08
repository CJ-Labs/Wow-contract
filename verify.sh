#!/bin/bash

# 验证 Coin 实现合约
forge verify-contract \
    --chain-id 133 \
    --verifier blockscout \
    --verifier-url https://hashkeychain-testnet-explorer.alt.technology/api \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" \
    "0x6ca0Df2886B55A3099bC70994b9aA8f29B455d50" \
    "0x6ca0Df2886B55A3099bC70994b9aA8f29B455d50" \
    "0x5FbDB2315678afecb367f032d93F642f64180aa3" \
    "0x0000000000000000000000000000000000000001" \
    "0x0000000000000000000000000000000000000002") \
    0x9dfe2189745625249b28c72edd71f72b8a57a0a7 \
    src/Coin.sol:Coin

# 验证 WowFactoryImpl 实现合约
forge verify-contract \
    --chain-id 133 \
    --verifier blockscout \
    --verifier-url https://hashkeychain-testnet-explorer.alt.technology/api \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address)" "0x9DfE2189745625249B28c72EdD71F72b8A57A0A7") \
    0xc8d37e8b30ceab4f267e26d402fc5dfd6130bad4 \
    src/WowFactoryImpl.sol:WowFactoryImpl

# 验证 ERC1967Proxy 代理合约
forge verify-contract \
    --chain-id 133 \
    --verifier blockscout \
    --verifier-url https://hashkeychain-testnet-explorer.alt.technology/api \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" \
    "0xC8D37e8B30Ceab4F267e26d402fc5DFD6130baD4" \
    "0xc4d66de80000000000000000000000006ca0df2886b55a3099bc70994b9aa8f29b455d50") \
    0x0f6e9b29bd1bdae2b442e314366e5c10088e541f \
    @openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
