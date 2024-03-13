// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {INFTPool, IPair} from "../e721-farms/camelotV2/interfaces/ICamelotV2.sol";
import {IUniswapV3PoolState} from "../e721-farms/uniswapV3/interfaces/IUniswapV3.sol";
import {IUniswapV3Utils} from "../e721-farms/uniswapV3/interfaces/IUniswapV3Utils.sol";

library TokenUtils {
    uint32 private constant MA_PERIOD = 10 minutes;

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
}
