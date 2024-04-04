// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {INFTPool, IPair} from "../e721-farms/camelotV2/interfaces/ICamelotV2.sol";
import {IUniswapV3PoolState} from "../e721-farms/uniswapV3/interfaces/IUniswapV3.sol";
import {IUniswapV3Utils} from "../e721-farms/uniswapV3/interfaces/IUniswapV3Utils.sol";
import {ICamelotV3Utils} from "../e721-farms/camelotV3/interfaces/ICamelotV3Utils.sol";
import {ICamelotV3PoolState} from "../e721-farms/camelotV3/interfaces/ICamelotV3.sol";

library TokenUtils {
    uint32 private constant MA_PERIOD = 10 minutes;

    /// @notice Get token amounts for Uniswap V2 farm based on the farm's liquidity.
    /// @param _nftContract pool address.
    /// @param _farmLiquidity The farm's liquidity.
    /// @return tokens An array of token addresses.
    /// @return amounts An array of token amounts.
    function getUniV2TokenAmounts(address _nftContract, uint256 _farmLiquidity)
        public
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](2);
        amounts = new uint256[](2);
        (address pair,,,,,,,) = INFTPool(_nftContract).getPoolInfo();
        tokens[0] = IPair(pair).token0();
        tokens[1] = IPair(pair).token1();
        (uint112 reserveA, uint112 reserveB,,) = IPair(pair).getReserves();
        uint256 _totalSupply = IPair(pair).totalSupply();
        amounts[0] = (_farmLiquidity * reserveA) / _totalSupply;
        amounts[1] = (_farmLiquidity * reserveB) / _totalSupply;
    }

    /// @notice Get token amounts for Uniswap V3 farm based on the farm's liquidity.
    /// @param _uniPool The Uniswap V3 pool address.
    /// @param _uniUtils The Uniswap V3 utils address.
    /// @param _tickLower The lower tick.
    /// @param _tickUpper The upper tick.
    /// @param _liquidity The farm's liquidity.
    /// @return tokens An array of token addresses.
    /// @return amounts An array of token amounts.
    function getUniV3TokenAmounts(
        address _uniPool,
        address _uniUtils,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _liquidity
    ) public view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = IUniswapV3PoolState(_uniPool).token0();
        tokens[1] = IUniswapV3PoolState(_uniPool).token1();

        uint32 oldestObservationSecondsAgo = IUniswapV3Utils(_uniUtils).getOldestObservationSecondsAgo(_uniPool);
        oldestObservationSecondsAgo = oldestObservationSecondsAgo < MA_PERIOD ? MA_PERIOD : oldestObservationSecondsAgo;
        (int24 timeWeightedAverageTick,) = IUniswapV3Utils(_uniUtils).consult(_uniPool, oldestObservationSecondsAgo);
        uint160 sqrtPriceX96 = IUniswapV3Utils(_uniUtils).getSqrtRatioAtTick(timeWeightedAverageTick);
        (amounts[0], amounts[1]) =
            IUniswapV3Utils(_uniUtils).getAmountsForLiquidity(sqrtPriceX96, _tickLower, _tickUpper, uint128(_liquidity));
    }

    /// @notice Get token amounts for Camelot V3 farm based on the farm's liquidity.
    /// @param _camelotPool The Camelot V3 pool address.
    /// @param _camelotUtils The Camelot V3 utils address.
    /// @param _tickLower The lower tick.
    /// @param _tickUpper The upper tick.
    /// @param _liquidity The farm's liquidity.
    /// @return tokens An array of token addresses.
    /// @return amounts An array of token amounts.
    function getCamelotV3TokenAmounts(
        address _camelotPool,
        address _camelotUtils,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _liquidity
    ) public view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = ICamelotV3PoolState(_camelotPool).token0();
        tokens[1] = ICamelotV3PoolState(_camelotPool).token1();
        (uint160 sqrtPriceX96,,,,,,,) = ICamelotV3PoolState(_camelotPool).globalState();
        (amounts[0], amounts[1]) = ICamelotV3Utils(_camelotUtils).getAmountsForLiquidity(
            sqrtPriceX96, _tickLower, _tickUpper, uint128(_liquidity)
        );
    }
}
