// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {RewardFund, RewardData, Deposit, Subscription} from "./interfaces/DataTypes.sol";

abstract contract BaseFarmStorage {
    // constants
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    uint256 public constant PREC = 1e18;
    uint256 public constant MIN_COOLDOWN_PERIOD = 1; // In days
    uint256 public constant MAX_COOLDOWN_PERIOD = 30; // In days
    uint256 public constant MAX_NUM_REWARDS = 4;

    // Global Params
    string public farmId;
    bool public isPaused;
    bool public isClosed;

    uint256 public cooldownPeriod;
    uint256 public lastFundUpdateTime;
    uint256 public totalDeposits;

    // Reward info
    RewardFund[] public rewardFunds;
    address[] public rewardTokens;
    mapping(address => RewardData) public rewardData;
    mapping(uint256 => Deposit) internal deposits;
    mapping(uint256 => Subscription[]) internal subscriptions;
}
