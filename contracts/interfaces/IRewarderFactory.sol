// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRewarderFactory {
    // Events.
    event OracleUpdated(address indexed newOracle);
    event RewarderDeployed(address indexed token, address indexed manager, address indexed rewarder);
    event RewarderImplementationUpdated(address indexed _newRewarderImplementation);

    // Custom Errors.
    error InvalidAddress();

    /// @notice Function to deploy new rewarder.
    /// @param _rwdToken Address of the reward token for which the rewarder is to be deployed.
    /// @return rewarder Rewarder's address.
    function deployRewarder(address _rwdToken) external returns (address rewarder);

    /// @notice Update rewarder implementation's address
    /// @param _newRewarderImplementation New Rewarder Implementation
    function updateRewarderImplementation(address _newRewarderImplementation) external;

    /// @notice Function to update the oracle's address.
    /// @param _newOracle Address of the new oracle.
    function updateOracle(address _newOracle) external;

    // --------------------- Public Variable(functions) ---------------------
    // Global Params.
    function oracle() external view returns (address);
    function rewarderImplementation() external view returns (address);
}
