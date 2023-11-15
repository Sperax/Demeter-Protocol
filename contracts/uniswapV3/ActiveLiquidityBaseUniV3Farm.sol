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
import {Deposit, Subscription, RewardFund} from "../interfaces/DataTypes.sol";

/// @title ActiveLiquidityBaseUniV3Farm
/// @notice This contract inherits the BaseUniV3Farm contract and implements the reward distribution only for active liquidity.
contract ActiveLiquidityBaseUniV3Farm is BaseUniV3Farm {
    uint256 public lastSecondsInside;

    /// @notice Function to compute the total accrued rewards for a deposit
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @return rewards The total accrued rewards for the deposit (uint256[])
    /// @dev This function is overridden from BaseFarm to incorporate reward distribution only for active liquidity.
    function computeRewards(address _account, uint256 _depositId)
        external
        view
        override
        returns (uint256[][] memory rewards)
    {
        _validateDeposit(_account, _depositId);
        Deposit memory userDeposit = deposits[_depositId];
        Subscription[] memory depositSubs = subscriptions[_depositId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numDepositSubs = depositSubs.length;
        uint256 numRewards = rewardTokens.length;
        rewards = new uint256[][](numDepositSubs);

        uint256 activeTime = 0;
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);

        // In case the reward is not updated.
        if (secondsInside > lastSecondsInside) {
            unchecked {
                activeTime = secondsInside - lastSecondsInside;
            }
        }

        // Update the two reward funds.
        for (uint8 iSub; iSub < numDepositSubs;) {
            Subscription memory sub = depositSubs[iSub];
            rewards[iSub] = new uint256[](numRewards);
            uint8 fundId = sub.fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
                if (funds[fundId].totalLiquidity != 0 && isFarmActive()) {
                    uint256 accRewards = _getAccRewards(iRwd, fundId, activeTime);
                    // update the accRewardPerShare for delta time.
                    funds[fundId].accRewardPerShare[iRwd] += (accRewards * PREC) / funds[fundId].totalLiquidity;
                }
                rewards[iSub][iRwd] =
                    ((userDeposit.liquidity * funds[fundId].accRewardPerShare[iRwd]) / PREC) - sub.rewardDebt[iRwd];
                unchecked {
                    ++iRwd;
                }
            }
            unchecked {
                ++iSub;
            }
        }
        return rewards;
    }

    /// @notice Returns if farm is active.
    ///         Farm is active if it is not paused and not closed.
    /// @return bool true if farm is active.
    /// @dev This function can be overridden to add any new/additional logic.
    function isFarmActive() public view override returns (bool) {
        return !isPaused && isFarmOpen() && !_isLiquidityActive();
    }

    /// @notice Function to update the FarmRewardData for all funds
    /// @dev This function is overridden from BaseFarm to incorporate reward distribution only for active liquidity.
    function _updateFarmRewardData() internal override {
        (,, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(tickLowerAllowed, tickUpperAllowed);
        if (secondsInside > lastSecondsInside) {
            // If farm is paused don't accrue any rewards.
            // only update the lastFundUpdateTime.
            if (isFarmActive()) {
                // Calculate the active liquidity time for the farm.
                uint256 activeTime;
                unchecked {
                    activeTime = secondsInside - lastSecondsInside;
                }
                uint256 numFunds = rewardFunds.length;
                uint256 numRewards = rewardTokens.length;
                // Update the reward funds.
                for (uint8 iFund; iFund < numFunds;) {
                    RewardFund storage fund = rewardFunds[iFund];
                    if (fund.totalLiquidity != 0) {
                        for (uint8 iRwd; iRwd < numRewards;) {
                            // Get the accrued rewards for the activeTime.
                            uint256 accRewards = _getAccRewards(iRwd, iFund, activeTime);
                            rewardData[rewardTokens[iRwd]].accRewardBal += accRewards;
                            fund.accRewardPerShare[iRwd] += (accRewards * PREC) / fund.totalLiquidity;

                            unchecked {
                                ++iRwd;
                            }
                        }
                    }
                    unchecked {
                        ++iFund;
                    }
                }
            }
            lastFundUpdateTime = block.timestamp;
            lastSecondsInside = secondsInside;
        }
    }

    function _isLiquidityActive() internal view returns (bool isActive) {
        (, int24 tick,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        if (tick >= tickLowerAllowed && tick <= tickUpperAllowed) {
            isActive = true;
        }
    }
}
