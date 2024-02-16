// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// Defines the reward data for constructor.
// token - Address of the token.
// tknManager - Authority to update rewardToken related params.
struct RewardTokenData {
    address token;
    address tknManager;
}

// Defines the reward funds for the farm.
// totalLiquidity - amount of liquidity sharing the rewards in the fund.
// rewardsPerSec - the emission rate of the fund.
// accRewardPerShare - the accumulated reward per share.
struct RewardFund {
    uint256 totalLiquidity;
    uint256[] rewardsPerSec;
    uint256[] accRewardPerShare;
}

// Keeps track of a deposit's share in a reward fund.
// fundId - id of the subscribed reward fund.
// rewardDebt - rewards claimed for a deposit corresponding to
//              latest accRewardPerShare value of the budget.
// rewardClaimed - rewards claimed for a deposit from the reward fund.
struct Subscription {
    uint8 fundId;
    uint256[] rewardDebt;
    uint256[] rewardClaimed;
}

// Deposit information:
// depositor - address of the depositor.
// liquidity - amount of liquidity in the deposit.
// startTime - time of deposit.
// expiryDate - expiry time (if deposit is locked).
// cooldownPeriod - cooldown period in seconds (if deposit is locked).
// totalRewardsClaimed - total rewards claimed for the deposit.
struct Deposit {
    address depositor;
    uint256 liquidity;
    uint256 startTime;
    uint256 expiryDate;
    uint256 cooldownPeriod;
    uint256[] totalRewardsClaimed;
}

// Reward token related information.
// tknManager - Address that manages the rewardToken.
// id - Id of the rewardToken in the rewardTokens array.
// accRewardBal - The rewards accrued but pending to be claimed.
struct RewardData {
    address tknManager;
    uint8 id;
    uint256 accRewardBal;
}
