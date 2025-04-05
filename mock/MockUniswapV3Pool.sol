// test/mocks/MockUniswapV3Pool.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    address public token0Override;
    address public token1Override;

    function slot0() external pure returns (Slot0 memory) {
        return Slot0({
            sqrtPriceX96: uint160(1),
            tick: 0,
            observationIndex: 0,
            observationCardinality: 0,
            observationCardinalityNext: 0,
            feeProtocol: 0,
            unlocked: true
        });
    }

    function feeGrowthGlobal0X128() external pure returns (uint256) {
        return 0;
    }

    function feeGrowthGlobal1X128() external pure returns (uint256) {
        return 0;
    }

    function token0() external view returns (address) {
        return token0Override;
    }

    function token1() external view returns (address) {
        return token1Override;
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        return (0, 0);
    }
}