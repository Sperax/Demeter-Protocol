// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFarmRegistry} from "./interfaces/IFarmRegistry.sol";

/// @title FarmDeployer contract of Demeter Protocol
/// @notice Exposes base functionalities which will be useful in every deployer
/// @author Sperax Foundation
abstract contract FarmDeployer is Ownable {
    using SafeERC20 for IERC20;

    address public immutable REGISTRY;
    // Stores the address of farmImplementation.
    address public farmImplementation;

    // Name of the farm
    string public farmId;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(address indexed creator, address token, uint256 amount);
    event FarmImplementationUpdated(address newFarmImplementation, string newFarmId);

    // Custom Errors
    error InvalidAddress();

    constructor(address _registry, string memory _farmId) {
        _validateNonZeroAddr(_registry);
        REGISTRY = _registry;
        farmId = _farmId;
    }

    /// @notice Update farm implementation's address
    /// @dev only callable by owner
    /// @param _newFarmImplementation New farm implementation's address
    function updateFarmImplementation(address _newFarmImplementation, string calldata _newFarmId) external onlyOwner {
        farmId = _newFarmId;
        farmImplementation = _newFarmImplementation;

        emit FarmImplementationUpdated(_newFarmImplementation, _newFarmId);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmRegistry.
    function _collectFee() internal virtual {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list
        (address feeReceiver, address feeToken, uint256 feeAmount,) = IFarmRegistry(REGISTRY).getFeeParams(msg.sender);
        if (feeAmount != 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
            emit FeeCollected(msg.sender, feeToken, feeAmount);
        }
    }

    /// @notice Validate address
    function _validateNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
