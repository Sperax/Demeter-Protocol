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

import {BaseFarm} from "./BaseFarm.sol";

abstract contract OperableDeposit {
    uint256 public constant PRECISION = 1e18;

    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    error DecreaseDepositNotPermitted();

    /// @notice Update subscription data of a deposit for increase in liquidity.
    /// @param _subscription Subscription for the deposit passed.
    /// @param _rewardFunds Reward funds added.
    /// @param _amount _amount to be increased.
    /// @param _numRewards Number of reward tokens added.
    function _updateSubscriptionForIncrease(
        BaseFarm.Subscription[] storage _subscription,
        BaseFarm.RewardFund[] storage _rewardFunds,
        uint256 _amount,
        uint256 _numRewards
    ) internal {
        uint256 numSubs = _subscription.length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = _subscription[iSub].rewardDebt;
            uint8 _fundId = _subscription[iSub].fundId;
            for (uint8 iRwd; iRwd < _numRewards;) {
                _rewardDebt[iRwd] += ((_amount * _rewardFunds[_fundId].accRewardPerShare[iRwd]) / PRECISION);
                unchecked {
                    ++iRwd;
                }
            }
            _rewardFunds[_fundId].totalLiquidity += _amount;
            unchecked {
                ++iSub;
            }
        }
    }

    /// @notice Update subscription data of a deposit after decrease in liquidity.
    /// @param _subscription Subscription for the deposit passed.
    /// @param _rewardFunds Reward funds added.
    /// @param _amount _amount to be decreased.
    /// @param _numRewards Number of reward tokens added.
    function _updateSubscriptionForDecrease(
        BaseFarm.Subscription[] storage _subscription,
        BaseFarm.RewardFund[] storage _rewardFunds,
        uint256 _amount,
        uint256 _numRewards
    ) internal {
        uint256 numSubs = _subscription.length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = _subscription[iSub].rewardDebt;
            uint8 _fundId = _subscription[iSub].fundId;
            for (uint8 iRwd; iRwd < _numRewards;) {
                _rewardDebt[iRwd] -= ((_amount * _rewardFunds[_fundId].accRewardPerShare[iRwd]) / PRECISION);
                unchecked {
                    ++iRwd;
                }
            }
            _rewardFunds[_fundId].totalLiquidity -= _amount;
            unchecked {
                ++iSub;
            }
        }
    }
}
