pragma solidity 0.8.16;

interface IUniswapV2Factory {
    function getPair(address _tokenA, address _tokenB)
        external
        view
        returns (address);

    function allPairs(uint256 _id) external view returns (address);

    function allPairsLength() external view returns (uint256);
}
