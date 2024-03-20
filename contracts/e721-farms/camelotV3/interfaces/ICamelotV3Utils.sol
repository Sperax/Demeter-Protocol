// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICamelotV3Utils {
    function getAmountsForLiquidity(uint160 sqrtRatioX96, int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        pure
        returns (uint256 amount0, uint256 amount1);
}
