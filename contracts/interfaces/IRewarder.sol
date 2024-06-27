// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRewarder {
    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // rewardRate - Amount of tokens emitted per second.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseAssetIndexes - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FarmRewardConfig {
        uint256 apr;
        uint128 rewardRate;
        uint128 maxRewardRate;
        uint256[] baseAssetIndexes;
        uint256 nonLockupRewardPer; // 5e3 = 50%.
    }

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseTokens - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FarmRewardConfigInput {
        uint256 apr;
        uint128 maxRewardRate;
        address[] baseTokens;
        uint256 nonLockupRewardPer; // 5e3 = 50%.
    }

    // Events.
    event RewardConfigUpdated(address indexed farm, FarmRewardConfigInput rewardConfig);
    event APRUpdated(address indexed farm, uint256 apr);
    event RewardCalibrated(address indexed farm, uint256 rewardsSent, uint256 rewardRate);
    event CalibrationRestrictionToggled(address indexed farm);

    // Custom Errors.
    error InvalidAddress();
    error InvalidFarm();
    error FarmNotConfigured(address farm);
    error ZeroAmount();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);
    error CalibrationRestricted(address farm);

    /// @notice Initializer function of this contract.
    /// @param _rwdToken Address of the reward token.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    function initialize(address _rwdToken, address _oracle, address _admin) external;

    /// @notice Function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateReward(address _farm) external returns (uint256 rewardsToSend);

    /// @notice Function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerOfFarm(address _farm, address _newManager) external;
    /// @notice Function to recover reward funds from the farm.
    /// @param _farm Farm's address from which reward funds is to be recovered.
    /// @param _amount Amount which is to be recovered.
    function recoverRewardFundsOfFarm(address _farm, uint256 _amount) external;
    /// @notice Function to update APR.
    /// @param _farm Address of the farm.
    /// @param _apr APR in 1e8 precision.
    function updateAPR(address _farm, uint256 _apr) external;

    /// @notice Function to toggle calibration restriction.
    /// @param _farm Address of farm for which calibration restriction is to be toggled.
    function toggleCalibrationRestriction(address _farm) external;

    /// @notice Function to recover ERC20 tokens from this contract.
    /// @param _token Address of the token.
    /// @param _amount Amount of the tokens.
    function recoverERC20(address _token, uint256 _amount) external;

    /// @notice Function to update the REWARD_TOKEN configuration.
    ///         This function calibrates reward so token manager must be updated to address of this contract in the farm.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, FarmRewardConfigInput memory _rewardConfig) external;

    /// @notice Function to get token amounts value of underlying pool of the farm.
    /// @param _farm Address of the farm.
    /// @return Array of token addresses.
    /// @return Array of token amounts.
    function getTokenAmounts(address _farm) external view returns (address[] memory, uint256[] memory);

    /// @notice Function to get reward config for a farm.
    /// @param _farm Address of the farm.
    /// @return FarmRewardConfig Farm reward config.
    function getFarmRewardConfig(address _farm) external view returns (FarmRewardConfig memory);

    /// @notice Function to calculate the time till which rewards are there for an LP.
    /// @param _farm Address of the farm for which the end time is to be calculated.
    /// @return rewardsEndingOn Timestamp in seconds till which the rewards are there in farm and in rewarder.
    function rewardsEndTime(address _farm) external view returns (uint256 rewardsEndingOn);

    // --------------------- Public Variable(functions) ---------------------

    // Constants.
    function MAX_PERCENTAGE() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function APR_PRECISION() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function REWARD_PERIOD() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function DENOMINATOR() external view returns (uint256); // solhint-disable-line func-name-mixedcase
    function ONE_YEAR() external view returns (uint256); // solhint-disable-line func-name-mixedcase

    // Global Params.
    function REWARD_TOKEN() external view returns (address); // solhint-disable-line func-name-mixedcase
    function REWARD_TOKEN_DECIMALS() external view returns (uint8); // solhint-disable-line func-name-mixedcase
    function totalRewardRate() external view returns (uint256);
    function rewarderFactory() external view returns (address);
}
