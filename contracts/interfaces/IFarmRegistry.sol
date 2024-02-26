// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFarmRegistry {
    function registerFarm(address farm, address creator) external;

    function registerFarmDeployer(address _deployer) external;

    function getFeeParams(address _deployerAccount)
        external
        view
        returns (address feeFeceiver, address feeToken, uint256 feeAmount, uint256 extensionFeePerDay);

    function isPrivilegedDeployer(address _user) external view returns (bool);

    function farmRegistered(address farm) external view returns (bool);
}
