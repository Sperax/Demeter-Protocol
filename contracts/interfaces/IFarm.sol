// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RewardData, RewardFund, Deposit, Subscription} from "./DataTypes.sol";

interface IFarm {
    // Events.
    event Deposited(uint256 indexed depositId, address indexed account, bool locked, uint256 liquidity);
    event CooldownInitiated(uint256 indexed depositId, uint256 expiryDate);
    event DepositWithdrawn(uint256 indexed depositId);
    event RewardsClaimed(uint256 indexed depositId, uint256[][] rewardsForEachSubs);
    event PoolUnsubscribed(uint256 indexed depositId, uint8 fundId, uint256[] totalRewardsClaimed);
    event PoolSubscribed(uint256 indexed depositId, uint8 fundId);
    event FarmStartTimeUpdated(uint256 newStartTime);
    event CooldownPeriodUpdated(uint256 newCooldownPeriod);
    event RewardRateUpdated(address indexed rwdToken, uint128[] newRewardRate);
    event RewardAdded(address indexed rwdToken, uint256 amount);
    event FarmClosed();
    event RecoveredERC20(address indexed token, uint256 amount);
    event FundsRecovered(address indexed account, address indexed rwdToken, uint256 amount);
    event RewardDataUpdated(address indexed rwdToken, address indexed newTokenManager);
    event RewardTokenAdded(address indexed rwdToken, address indexed rwdTokenManager);
    event FarmPaused(bool paused);

    // Custom Errors
    error InvalidRewardToken();
    error FarmDoesNotSupportLockup();
    error FarmAlreadyStarted();
    error InvalidTime();
    error FarmAlreadyInRequiredState();
    error CannotWithdrawRewardToken();
    error CannotWithdrawZeroAmount();
    error SubscriptionDoesNotExist();
    error RewardFundDoesNotExist();
    error LockupFunctionalityIsDisabled();
    error NoLiquidityInPosition();
    error CannotInitiateCooldown();
    error PleaseInitiateCooldown();
    error DepositIsInCooldown();
    error InvalidRewardRatesLength();
    error InvalidFundId();
    error InvalidFarmStartTime();
    error InvalidRewardData();
    error RewardTokenAlreadyAdded();
    error DepositDoesNotExist();
    error FarmIsClosed();
    error FarmIsInactive();
    error NotTheTokenManager();
    error InvalidAddress();
    error ZeroAmount();
    error InvalidCooldownPeriod();
    error WithdrawTooSoon();

    /// @notice Function to be called to withdraw deposit.
    /// @param _depositId The id of the deposit.
    function withdraw(uint256 _depositId) external;

    /// @notice A function to be called by the depositor to claim rewards.
    /// @param _depositId The id of the deposit.
    function claimRewards(uint256 _depositId) external;

    /// @notice Function to be called to initiate cooldown for a staked deposit.
    /// @param _depositId The id of the deposit to be locked.
    /// @dev _depositId is corresponding to the user's deposit.
    function initiateCooldown(uint256 _depositId) external;

    /// @notice Add rewards to the farm.
    /// @param _rwdToken The reward token's address.
    /// @param _amount The amount of reward tokens to add.
    function addRewards(address _rwdToken, uint256 _amount) external;

    // --------------------- Admin  Functions ---------------------

    /// @notice Update the cooldown period.
    /// @param _newCooldownPeriod The new cooldown period (in days). E.g: 7 means 7 days.
    function updateCooldownPeriod(uint256 _newCooldownPeriod) external;

    /// @notice Pause / UnPause the farm.
    /// @param _isPaused Desired state of the farm (true to pause the farm).
    function farmPauseSwitch(bool _isPaused) external;

    /// @notice A function to explicitly close the farm.
    /// @dev Recovers remaining non accrued rewards.
    /// @dev Sets reward rate to 0 and shuts down the farm completely.
    function closeFarm() external;

    /// @notice Recover erc20 tokens other than the reward tokens.
    /// @param _token Address of token to be recovered.
    function recoverERC20(address _token) external;

    // --------------------- Token Manager Functions ---------------------
    /// @notice Get the remaining reward balance out of the farm.
    /// @param _rwdToken The reward token's address.
    /// @param _amount The amount of the reward tokens to be withdrawn.
    /// @dev Function recovers minOf(_amount, rewardsLeft).
    function recoverRewardFunds(address _rwdToken, uint256 _amount) external;

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address.
    /// @param _newRewardRates The new reward rate for the fund (includes the precision).
    function setRewardRate(address _rwdToken, uint128[] memory _newRewardRates) external;

    /// @notice Transfer the tokenManagerRole to other user.
    /// @dev Only the existing tokenManager for a reward can call this function.
    /// @param _rwdToken The reward token's address.
    /// @param _newTknManager Address of the new token manager.
    function updateRewardData(address _rwdToken, address _newTknManager) external;

    /// @notice Function to update the FarmRewardData for all funds.
    function updateFarmRewardData() external;

    /// @notice Claim rewards and send it to another account.
    /// @param _account To receive the rewards.
    /// @param _depositId The id of the deposit.
    /// @dev Only the depositor can call this function.
    function claimRewardsTo(address _account, uint256 _depositId) external;

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start.
    ///      New start time should be in future.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) external;

    /// @notice Function to compute the total accrued rewards for a deposit for each subscription.
    /// @param _account The user's address.
    /// @param _depositId The id of the deposit.
    /// @return rewards The total accrued rewards for the deposit for each subscription (uint256[][]).
    function computeRewards(address _account, uint256 _depositId) external view returns (uint256[][] memory rewards);

    /// @notice Get deposit info for a deposit id.
    /// @param _depositId The id of the deposit.
    /// @return The deposit info (Deposit).
    function getDepositInfo(uint256 _depositId) external view returns (Deposit memory);

    /// @notice Get number of subscriptions for an account.
    /// @param _depositId The deposit id.
    /// @return The number of subscriptions for the deposit.
    function getNumSubscriptions(uint256 _depositId) external view returns (uint256);

    /// @notice Get subscription stats for a deposit.
    /// @param _depositId The deposit id.
    /// @param _subscriptionId The subscription's id.
    /// @return The subscription info (Subscription).
    function getSubscriptionInfo(uint256 _depositId, uint256 _subscriptionId)
        external
        view
        returns (Subscription memory);

    /// @notice Get reward rates for a rewardToken.
    /// @param _rwdToken The reward token's address.
    /// @return The reward rates for the reward token (uint256[]).
    function getRewardRates(address _rwdToken) external view returns (uint256[] memory);

    /// @notice Get farm reward fund info.
    /// @param _fundId The fund's id.
    /// @return The reward fund info (RewardFund).
    function getRewardFundInfo(uint8 _fundId) external view returns (RewardFund memory);

    /// @notice Function to get the reward tokens added in the farm.
    /// @return The reward tokens added in the farm.
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    /// @return Tokens associated with the farm's pool.
    /// @return Amounts associated with the farm's liquidity.
    /// @dev This function should be overridden to add the respective logic.
    function getTokenAmounts() external view returns (address[] memory, uint256[] memory);

    /// @notice Returns if farm is open.
    ///         Farm is open if it is not closed.
    /// @return bool True if farm is open.
    /// @dev This function can be overridden to add any new/additional logic.
    function isFarmOpen() external view returns (bool);

    /// @notice Returns if farm is active.
    ///         Farm is active if it is not paused and not closed.
    /// @return bool True if farm is active.
    /// @dev This function can be overridden to add any new/additional logic.
    function isFarmActive() external view returns (bool);

    /// @notice Get the reward balance for specified reward token.
    /// @param _rwdToken The address of the reward token.
    /// @return The available reward balance for the specified reward token.
    /// @dev This function calculates the available reward balance by considering the accrued rewards and the token supply.
    function getRewardBalance(address _rwdToken) external view returns (uint256);

    /// @notice Get the reward fund details.
    /// @return The available reward funds' details for all the reward funds.
    function getRewardFunds() external view returns (RewardFund[] memory);

    /// @notice Get the reward details for specified reward token.
    /// @param _rwdToken The address of the reward token.
    /// @return The available reward details for the specified reward token.
    function getRewardData(address _rwdToken) external view returns (RewardData memory);

    // --------------------- Public Variable(functions) ---------------------

    // Constants.
    function COMMON_FUND_ID() external view returns (uint8); // solhint-disable-line func-name-mixedcase
    function LOCKUP_FUND_ID() external view returns (uint8); // solhint-disable-line func-name-mixedcase
    function PRECISION() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function MAX_COOLDOWN_PERIOD() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function MAX_NUM_REWARDS() external view returns (uint256); // solhint-disable-line func-name-mixedcase

    // Global Params.
    function farmId() external view returns (string memory);
    function cooldownPeriod() external view returns (uint256);
    function lastFundUpdateTime() external view returns (uint256);
    function farmStartTime() external view returns (uint256);
    function totalDeposits() external view returns (uint256);
}
