// This contract is for testing purpose (Arbitrum)
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../../uniswapV3/tests/ISwapRouter.sol";
import {INonfungiblePositionManager} from "../../uniswapV3/interfaces/UniswapV3.sol";

/**
 * @title Token Swapping on SushiswapV3 Arbitrum
 * @notice Sushiswap V3 is a fork of Uniswap V3 with some modifications so the below reference is still valid
 * @dev reference: https://docs.uniswap.org/protocol/guides/swaps/single-swaps
 * @author Sperax Foundation
 */
contract SushiswapV3Test {
    using SafeERC20 for IERC20;
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49);

    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0x8A21F6768C1f8075791D08546Dadf6daA0bE820c);

    event SwapTest(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice swaps a fixed amount of inputToken for a maximum possible amount of outputToken on Sushiswap V3
     */
    function swap(
        address inputToken,
        address outputToken,
        uint24 poolFee,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        IERC20(inputToken).safeApprove(address(SWAP_ROUTER), amountIn);
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
        amountOut = SWAP_ROUTER.exactInputSingle(params);
        emit SwapTest(inputToken, outputToken, amountIn, amountOut);
    }
}
