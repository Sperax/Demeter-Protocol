pragma solidity 0.8.10;

interface IFarm {
    /// @notice Add rewards to the farm.
    /// @param _rwdToken the reward token's address.
    /// @param _amount the amount of reward tokens to add.
    function addRewards(address _rwdToken, uint256 _amount) external;

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address
    /// @param _newRewardRates The new reward rate for the fund (includes the precision)
    function setRewardRate(address _rwdToken, uint256[] memory _newRewardRates)
        external;

    /// @notice Transfer the tokenManagerRole to other user.
    /// @dev Only the existing tokenManager for a reward can call this function.
    /// @param _rwdToken The reward token's address.
    /// @param _newTknManager Address of the new token manager.
    function updateTokenManager(address _rwdToken, address _newTknManager)
        external;

    /// @notice Get the remaining balance out of the  farm
    /// @param _rwdToken The reward token's address
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    function recoverRewardFunds(address _rwdToken, uint256 _amount) external;

    /// @notice Function returns the cooldown period for the the farm
    function cooldownPeriod() external view returns (uint256);

    function isPaused() external view returns (bool);
}
