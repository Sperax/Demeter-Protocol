// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICamelotFarm {
    function nftPool() external view returns (address);
    function FARM_ID() external view returns (string memory);
}

interface IUniswapV3Farm {
    function uniswapPool() external view returns (address);
    function tickLowerAllowed() external view returns (int24);
    function tickUpperAllowed() external view returns (int24);
}
