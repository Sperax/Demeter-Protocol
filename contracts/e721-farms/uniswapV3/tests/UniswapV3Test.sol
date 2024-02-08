// This contract is for testing purpose (Arbitrum)
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {INonfungiblePositionManager} from "../interfaces/IUniswapV3.sol";

/**
 * @title Token Swapping on UniswapV3 Arbitrum
 * @dev reference: https://docs.uniswap.org/protocol/guides/swaps/single-swaps
 * @author Sperax Foundation
 */
contract UniswapV3Test {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public nonfungiblePositionManager;

    ISwapRouter public immutable SWAP_ROUTER;

    event SwapTest(address inputToken, address outputToken, uint256 amountIn, uint256 amountOut);

    // uniswap-v3 data
    // nonfungiblePositionManager address -> 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
    // SWAP_ROUTER address -> 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45

    // sushiswap-v3 data
    // nonfungiblePositionManager address -> 0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49
    // SWAP_ROUTER address -> 0x8A21F6768C1f8075791D08546Dadf6daA0bE820c

    constructor(address _nfpm, address _swapRouter) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nfpm);
        SWAP_ROUTER = ISwapRouter(_swapRouter);
    }

    /**
     * @notice swaps a fixed amount of inputToken for a maximum possible amount of outputToken on Uniswap V3
     */
    function swap(address inputToken, address outputToken, uint24 poolFee, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        IERC20(inputToken).forceApprove(address(SWAP_ROUTER), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
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
