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

import {RewardFund, RewardData, Deposit, Subscription} from "./interfaces/DataTypes.sol";

/// @title FarmStorage contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract contains the base storage variables for farms.
abstract contract FarmStorage {
    // constants.
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_COOLDOWN_PERIOD = 30; // in days.
    uint256 public constant MAX_NUM_REWARDS = 4;

    // Global Params.
    string public farmId;
    bool internal isPaused;
    bool internal isClosed;

    uint256 public cooldownPeriod;
    uint256 public lastFundUpdateTime;
    uint256 public farmStartTime;
    uint256 public totalDeposits;

    // Reward info.
    RewardFund[] public rewardFunds;
    address[] internal rewardTokens;
    mapping(address => RewardData) public rewardData;
    mapping(uint256 => Deposit) internal deposits;
    mapping(uint256 => Subscription[]) internal subscriptions;
}
