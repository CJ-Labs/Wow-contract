<!--
parent:
  order: false
-->

<div align="center">
  <h1> Fishcake Contracts Repo</h1>
</div>

<div align="center">
  <a href="https://github.com/FishcakeLab/fishcake-contracts/releases/latest">
    <img alt="Version" src="https://img.shields.io/github/tag/FishcakeLab/fishcake-contracts.svg" />
  </a>
  <a href="https://github.com/FishcakeLab/fishcake-contracts/blob/main/LICENSE">
    <img alt="License: Apache-2.0" src="https://img.shields.io/github/license/FishcakeLab/fishcake-contracts.svg" />
  </a>
</div>

Fishcake Contracts Project

## Installation

For prerequisites and detailed build instructions please read the [Installation](https://github.com/FishcakeLab/fishcake-contracts/) instructions. Once the dependencies are installed, run:

```bash
git submodule update --init --recursive --remote
```
or
```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-commit
forge install transmissions11/solmate --no-commit

```

Or check out the latest [release](https://github.com/FishcakeLab/fishcake-contracts).


## .env
```
PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```


## test
```
forge test 
```

## Depoly

```
local
forge script script/DeployScript.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast -vvvvv


forge script script/DeployScript.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast --verify -vvvvv

```


## test

```
# 运行所有测试
forge test -vvvvv

# 运行特定测试（例如）
forge test --match-test test_DeployCoin -vv

# 查看测试覆盖率
forge coverage

```