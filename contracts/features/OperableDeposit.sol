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

import {BaseFarmWithExpiry} from "./BaseFarmWithExpiry.sol";
import {Subscription, RewardFund} from "../interfaces/DataTypes.sol";

abstract contract OperableDeposit is BaseFarmWithExpiry {
    uint256 public constant PRECISION = 1e18;

    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    error DecreaseDepositNotPermitted();

    /// @notice Update subscription data of a deposit for increase in liquidity.
    /// @param _depositId Unique deposit id for the deposit
    /// @param _amount _amount to be increased.
    function _updateSubscriptionForIncrease(uint256 _depositId, uint256 _amount) internal {
        uint256 numRewards = rewardTokens.length;
        Subscription[] storage _subscriptions = subscriptions[_depositId];
        RewardFund[] storage _rewardFunds = rewardFunds;
        uint256 numSubs = _subscriptions.length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = _subscriptions[iSub].rewardDebt;
            uint8 _fundId = _subscriptions[iSub].fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
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
    /// @param _depositId Unique deposit id for the deposit
    /// @param _amount _amount to be decreased.
    function _updateSubscriptionForDecrease(uint256 _depositId, uint256 _amount) internal {
        uint256 numRewards = rewardTokens.length;
        Subscription[] storage _subscriptions = subscriptions[_depositId];
        RewardFund[] storage _rewardFunds = rewardFunds;
        uint256 numSubs = _subscriptions.length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = _subscriptions[iSub].rewardDebt;
            uint8 _fundId = _subscriptions[iSub].fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
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

    function _increaseDepositCommon(uint256 _depositId) internal {
        // Validations
        _validateFarmActive(); // Increase deposit is allowed only when farm is active.
        _validateDeposit(msg.sender, _depositId);
        if (deposits[_depositId].expiryDate != 0) {
            revert DepositIsInCooldown();
        }
        // claim the pending rewards for the deposit
        _updateAndClaimFarmRewards(msg.sender, _depositId);
    }

    function _decreaseDepositCommon(uint256 _depositId) internal {
        //Validations
        _validateFarmOpen(); // Withdraw instead of decrease deposit when farm is closed.
        _validateDeposit(msg.sender, _depositId);
        if (deposits[_depositId].expiryDate != 0 || deposits[_depositId].cooldownPeriod != 0) {
            revert DecreaseDepositNotPermitted();
        }
        // claim the pending rewards for the deposit
        _updateAndClaimFarmRewards(msg.sender, _depositId);
    }
}
