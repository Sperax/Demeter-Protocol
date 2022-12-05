// This contract is for testing purpose (Arbitrum)
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "../interfaces/UniswapV3.sol";

/**
 * @title Token Swapping on UniswapV3 Arbitrum
 * @dev reference: https://docs.uniswap.org/protocol/guides/swaps/single-swaps
 * @author Sperax Foundation
 */
contract UniswapV3Test {
    using SafeERC20 for IERC20;
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ISwapRouter public constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    event SwapTest(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice swaps a fixed amount of inputToken for a maximum possible amount of outputToken on Uniswap V3
     */
    function swap(
        address inputToken,
        address outputToken,
        uint24 poolFee,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        IERC20(inputToken).safeApprove(address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inputToken,
                tokenOut: outputToken,
                fee: poolFee,
                recipient: msg.sender,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        // Executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
        emit SwapTest(inputToken, outputToken, amountIn, amountOut);
    }
}
