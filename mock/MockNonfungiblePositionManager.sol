// test/mocks/MockNonfungiblePositionManager.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {MockUniswapV3Pool} from "./MockUniswapV3Pool.sol";

contract MockNonfungiblePositionManager is INonfungiblePositionManager {
    address public mockPool;
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => Position) private _positions;

    constructor() {
        mockPool = address(new MockUniswapV3Pool());
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool) {
        return mockPool;
    }

    function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = nextTokenId++;
        _owners[tokenId] = msg.sender;
        liquidity = 1000;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: mockPool,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }

    function collect(CollectParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1)
    {
        amount0 = 1 ether;
        amount1 = 1 ether;
    }

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
    )
    {
        Position memory position = _positions[tokenId];
        MockUniswapV3Pool pool = MockUniswapV3Pool(position.poolId);

        return (
            position.nonce,
            position.operator,
            pool.token0(),    // token0
            pool.token1(),    // token1
            3000,             // fee (0.3%)
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }


    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        _owners[tokenId] = to;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external {
        _owners[tokenId] = to;
    }
}