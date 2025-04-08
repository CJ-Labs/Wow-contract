// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// WowFactory 接口定义
interface IWowFactory {
    /// @notice 当新的 Wow 代币被创建时发出的事件
    /// @param factoryAddress 创建代币的工厂合约地址
    /// @param creator 代币创建者的地址
    /// @param platformReferrer 平台推荐人的地址
    /// @param protocolFeeRecipient 协议费用接收者的地址
    /// @param bondingCurve 绑定曲线合约的地址
    /// @param tokenURI 代币的 URI
    /// @param name 代币名称
    /// @param symbol 代币符号
    /// @param tokenAddress 代币合约地址
    /// @param poolAddress 流动性池合约地址
    event WowTokenCreated(
        address indexed factoryAddress,
        address indexed creator,
        address platformReferrer,
        address protocolFeeRecipient,
        address bondingCurve,
        string tokenURI,
        string name,
        string symbol,
        address tokenAddress,
        address poolAddress
    );

    /// @notice 当新的 Coin 被创建时发出的事件
    /// @param deployer 创建 Coin 的 msg.sender 地址
    /// @param creator Coin 创建者的地址
    /// @param creatorPayoutRecipient 创建者收益接收者的地址
    /// @param platformReferrer 平台推荐人的地址
    /// @param currency Coin 的货币地址
    /// @param tokenURI Coin 的 URI
    /// @param name Coin 的名称
    /// @param symbol Coin 的符号
    /// @param coin Coin 的合约地址
    /// @param pool 流动性池合约地址
    event CoinCreated(
        address indexed deployer,
        address indexed creator,
        address indexed creatorPayoutRecipient,
        address platformReferrer,
        address currency,
        string tokenURI,
        string name,
        string symbol,
        address coin,
        address pool
    );

    /// @notice 部署一个 Coin
    /// @param _creator 代币创建者的地址
    /// @param _platformReferrer 平台推荐人的地址
    /// @param _tokenURI ERC20z 代币的 URI
    /// @param _name ERC20 代币的名称
    /// @param _symbol ERC20 代币的符号
    function deploy(
        address _creator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol
    ) external payable returns (address);
}
