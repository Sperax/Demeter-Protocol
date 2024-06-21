// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@***@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(****@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@((******@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(((*******@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@((((********@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@(((((********@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@(((((((********@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@(((((((/*******@@@@@@@ //
// @@@@@@@@@@&*****@@@@@@@@@@(((((((*******@@@@@ //
// @@@@@@***************@@@@@@@(((((((/*****@@@@ //
// @@@@********************@@@@@@@(((((((****@@@ //
// @@@************************@@@@@@(/((((***@@@ //
// @@@**************@@@@@@@@@***@@@@@@(((((**@@@ //
// @@@**************@@@@@@@@*****@@@@@@*((((*@@@ //
// @@@**************@@@@@@@@@@@@@@@@@@@**(((@@@@ //
// @@@@***************@@@@@@@@@@@@@@@@@**((@@@@@ //
// @@@@@****************@@@@@@@@@@@@@****(@@@@@@ //
// @@@@@@@*****************************/@@@@@@@@ //
// @@@@@@@@@@************************@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@***************@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //

import {UniV3Farm} from "./UniV3Farm.sol";
import {IUniswapV3PoolDerivedState, IUniswapV3PoolState} from "./interfaces/IUniswapV3.sol";

/// @title UniV3ActiveLiquidityFarm.
/// @author Sperax Foundation.
/// @notice This contract inherits the UniV3Farm contract and implements the reward distribution only for active liquidity.
contract UniV3ActiveLiquidityFarm is UniV3Farm {
    uint32 public lastSecondsInside;

    /// @notice Returns if farm is active.
    ///         Farm is active if it is not paused, not closed, and liquidity is active.
    /// @return bool True if farm is active.
    /// @dev This function checks if current tick is within this farm's tick range.
    function isFarmActive() public view override returns (bool) {
        return super.isFarmActive() && _isLiquidityActive();
    }

    /// @notice Update the last reward accrual time.
    /// @dev This function is overridden from Farm to incorporate reward distribution only for active liquidity.
    function _updateLastRewardAccrualTime() internal override {
        super._updateLastRewardAccrualTime();
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);
        lastSecondsInside = secondsInside;
    }

    /// @notice Get the time elapsed since the last reward accrual.
    /// @return time The time elapsed since the last reward accrual.
    /// @dev This function is overridden from Farm to incorporate reward distribution only for active liquidity.
    function _getRewardAccrualTimeElapsed() internal view override returns (uint256) {
        if (farmStartTime > block.timestamp || lastSecondsInside == 0) return 0; // Farm has not started
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);
        return secondsInside - lastSecondsInside;
    }

    function _isLiquidityActive() internal view returns (bool) {
        (, int24 tick,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        return (tick >= tickLowerAllowed && tick <= tickUpperAllowed);
    }
}
