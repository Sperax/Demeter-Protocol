// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ICamelotV3Utils {
    function fees(address positionManager, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);
}
