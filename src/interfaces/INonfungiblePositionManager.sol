// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface INonfungiblePositionManager {
    // 铸造新头寸所需的参数结构
    struct MintParams {
        address token0;        // 第一个代币的地址
        address token1;        // 第二个代币的地址
        uint24 fee;           // 交易手续费比例
        int24 tickLower;      // 价格范围下限
        int24 tickUpper;      // 价格范围上限
        uint256 amount0Desired;  // 期望存入的 token0 数量
        uint256 amount1Desired;  // 期望存入的 token1 数量
        uint256 amount0Min;    // 最少接受的 token0 数量
        uint256 amount1Min;    // 最少接受的 token1 数量
        address recipient;     // 接收 NFT 的地址
        uint256 deadline;      // 交易截止时间
    }

    // 收取手续费的参数结构
    struct CollectParams {
        uint256 tokenId;      // NFT 的 ID
        address recipient;     // 接收手续费的地址
        uint128 amount0Max;   // 最大收取的 token0 数量
        uint128 amount1Max;   // 最大收取的 token1 数量
    }

    // 头寸信息结构体
    struct Position {
        uint96 nonce;         // 用于许可的随机数
        address operator;     // 操作者地址
        address poolId;       // 池子地址
        int24 tickLower;      // 价格区间下限
        int24 tickUpper;      // 价格区间上限
        uint128 liquidity;    // 流动性数量
        uint256 feeGrowthInside0LastX128;  // token0 的累计手续费
        uint256 feeGrowthInside1LastX128;  // token1 的累计手续费
        uint128 tokensOwed0;  // 待领取的 token0 数量
        uint128 tokensOwed1;  // 待领取的 token1 数量
    }

    /// @notice 创建池子，如果池子不存在则创建并初始化
    /// @dev 此方法可以与其他方法通过 IMulticall 组合使用，用于对池子的首次操作（例如铸造）
    /// @param token0 池子的第一个代币的合约地址
    /// @param token1 池子的第二个代币的合约地址
    /// @param fee 指定代币对的 v3 池的手续费比例
    /// @param sqrtPriceX96 池子的初始平方根价格，作为 Q64.96 值
    /// @return pool 返回基于代币对和手续费的池子地址，如果需要会返回新创建的池子地址
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    /// @notice 创建头寸并铸造 NFT
    /// @dev 调用此函数时需确保池子已存在并已初始化
    /// @param params 铸造头寸所需的参数，使用 MintParams 结构编码
    /// @return tokenId 代表铸造头寸的 NFT 的 ID
    /// @return liquidity 该头寸的流动性数量
    /// @return amount0 实际存入的 token0 数量
    /// @return amount1 实际存入的 token1 数量
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice 为指定的头寸收取手续费
    /// @param params 包含 NFT ID、接收地址和最大收取数量的参数
    /// @return amount0 收取的 token0 数量
    /// @return amount1 收取的 token1 数量
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice 返回与给定 token ID 关联的头寸信息
    /// @dev 如果 token ID 无效则抛出异常
    /// @param tokenId 代表头寸的 token ID
    /// @return nonce 用于许可的随机数
    /// @return operator 被批准的操作者地址
    /// @return token0 特定池子的 token0 地址
    /// @return token1 特定池子的 token1 地址
    /// @return fee 池子关联的手续费比例
    /// @return tickLower 头寸的价格范围下限
    /// @return tickUpper 头寸的价格范围上限
    /// @return liquidity 头寸的流动性数量
    /// @return feeGrowthInside0LastX128 头寸最后一次操作时 token0 的累计手续费增长
    /// @return feeGrowthInside1LastX128 头寸最后一次操作时 token1 的累计手续费增长
    /// @return tokensOwed0 头寸最后一次计算时未领取的 token0 数量
    /// @return tokensOwed1 头寸最后一次计算时未领取的 token1 数量
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function approve(address to, uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /// @notice NFT 所有权转移事件
    /// @dev 由于四舍五入，报告的数量可能与实际转移的数量不完全相等
    /// @param tokenId 收取手续费的 NFT ID
    /// @param recipient 接收手续费的地址
    /// @param amount0 收取的 token0 数量
    /// @param amount1 收取的 token1 数量
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);
}
