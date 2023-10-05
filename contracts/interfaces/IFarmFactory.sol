// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFarmFactory {
    function registerFarm(address farm, address creator) external;

    function getFeeParams()
        external
        view
        returns (
            address feeFeceiver,
            address feeToken,
            uint256 feeAmount
        );

    function isPrivilegedDeployer(address _user) external view returns (bool);
}
