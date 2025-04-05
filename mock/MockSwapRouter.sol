// test/mocks/MockSwapRouter.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwapRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    function exactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    returns (uint256 amountOut)
    {
        // 1. 将输入代币从用户转移到路由合约
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // 2. 将代币转给接收者
        IERC20(params.tokenIn).safeTransfer(params.recipient, params.amountIn);

        // 3. 返回输出金额（在模拟环境中，简单返回输入金额）
        return params.amountIn;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
    external
    payable
    returns (uint256 amountIn)
    {
        return params.amountOut;
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // 空实现
    }

    // 接收 ETH 的回退函数
    receive() external payable {}
}