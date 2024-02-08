// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@&....(@@@@@@@@@@@@@..../@@@@@@@@@//
//@@@@@@........../@@@@@@@........../@@@@@@//
//@@@@@............(@@@@@............(@@@@@//
//@@@@@(............@@@@@(...........&@@@@@//
//@@@@@@@...........&@@@@@@.........@@@@@@@//
//@@@@@@@@@@@@@@%..../@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@...@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@......(&@@@@@@@@@@@@//
//@@@@@@#.........@@@@@@#...........@@@@@@@//
//@@@@@/...........%@@@@@............%@@@@@//
//@@@@@............#@@@@@............%@@@@@//
//@@@@@@..........#@@@@@@@/.........#@@@@@@//
//@@@@@@@@@&/.(@@@@@@@@@@@@@@&/.(&@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//

import {BaseUniV3Farm} from "./BaseUniV3Farm.sol";
import {IUniswapV3PoolDerivedState, IUniswapV3PoolState} from "./interfaces/IUniswapV3.sol";

/// @title BaseUniV3ActiveLiquidityFarm
/// @notice This contract inherits the BaseUniV3Farm contract and implements the reward distribution only for active liquidity.
contract BaseUniV3ActiveLiquidityFarm is BaseUniV3Farm {
    uint32 public lastSecondsInside;

    /// @notice Returns if farm is active.
    ///         Farm is active if it is not paused, not closed, and liquidity is active.
    /// @return bool true if farm is active.
    /// @dev This function checks if current tick is within this farm's tick range.
    function isFarmActive() public view override returns (bool) {
        return super.isFarmActive() && _isLiquidityActive();
    }

    /// @notice Update the last reward accrual time.
    /// @dev This function is overridden from BaseFarm to incorporate reward distribution only for active liquidity.
    function _updateLastRewardAccrualTime() internal override {
        super._updateLastRewardAccrualTime();
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);
        lastSecondsInside = secondsInside;
    }

    /// @notice Get the time elapsed since the last reward accrual.
    /// @return time The time elapsed since the last reward accrual.
    /// @dev This function is overridden from BaseFarm to incorporate reward distribution only for active liquidity.
    function _getRewardAccrualTimeElapsed() internal view override returns (uint256) {
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);
        return secondsInside - lastSecondsInside;
    }

    function _isLiquidityActive() internal view returns (bool) {
        (, int24 tick,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        return (tick >= tickLowerAllowed && tick <= tickUpperAllowed);
    }
}
