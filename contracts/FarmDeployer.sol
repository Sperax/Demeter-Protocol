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

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFarmRegistry} from "./interfaces/IFarmRegistry.sol";

/// @title FarmDeployer contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice Exposes base functionalities which will be useful in every deployer.
abstract contract FarmDeployer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable FARM_REGISTRY;
    // Stores the address of farmImplementation.
    address public farmImplementation;

    // Id of the farm.
    string public farmId;

    // Events.
    event FarmCreated(address indexed farm, address indexed creator, address indexed admin);
    event FeeCollected(address indexed creator, address indexed token, uint256 amount);
    event FarmImplementationUpdated(address indexed newFarmImplementation, string newFarmId);

    // Custom Errors
    error InvalidAddress();
    error NewFarmImplementationSameAsOld();

    /// @notice Constructor.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    constructor(address _farmRegistry, string memory _farmId) Ownable(msg.sender) {
        _validateNonZeroAddr(_farmRegistry);
        FARM_REGISTRY = _farmRegistry;
        farmId = _farmId;
    }

    /// @notice Update farm implementation's address.
    /// @dev Only callable by the owner.
    /// @param _newFarmImplementation New farm implementation's address.
    /// @param _newFarmId  ID of the new farm.
    /// @dev Ensure that `_newFarmId` is correct for the new farm implementation.
    function updateFarmImplementation(address _newFarmImplementation, string calldata _newFarmId) external onlyOwner {
        _validateNonZeroAddr(_newFarmImplementation);

        if (farmImplementation == _newFarmImplementation) {
            revert NewFarmImplementationSameAsOld();
        }

        farmId = _newFarmId;
        farmImplementation = _newFarmImplementation;

        emit FarmImplementationUpdated(_newFarmImplementation, _newFarmId);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmRegistry.
    function _collectFee() internal virtual {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list.
        (address feeReceiver, address feeToken, uint256 feeAmount,) =
            IFarmRegistry(FARM_REGISTRY).getFeeParams(msg.sender);
        if (feeAmount != 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
            emit FeeCollected(msg.sender, feeToken, feeAmount);
        }
    }

    /// @notice Validate address.
    function _validateNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
