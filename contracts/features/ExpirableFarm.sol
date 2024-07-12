// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
import {Farm} from "../Farm.sol";
import {IFarmRegistry} from "../interfaces/IFarmRegistry.sol";

/// @title  ExpirableFarm contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract helps in creating farms with expiry feature.
abstract contract ExpirableFarm is Farm {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_EXTENSION = 100; // 100 days.
    uint256 public constant MAX_EXTENSION = 300; // 300 days.
    uint256 public farmEndTime;
    address public farmRegistry;

    event FarmEndTimeUpdated(uint256 newEndTime);
    event ExtensionFeeCollected(address indexed token, uint256 extensionFee);

    error InvalidExtension();
    error DurationExceeded();
    error FarmNotYetStarted();

    /// @notice Update the farm end time.
    /// @dev Can be updated only before the farm expired or closed.
    ///      Extension should be incremented in multiples of 1 USDs/day with minimum of 100 days at a time and a maximum of 300 days.
    ///      Extension is possible only after farm started.
    /// @param _extensionDays The number of days to extend the farm. Example: 150 means 150 days.
    function extendFarmDuration(uint256 _extensionDays) external onlyOwner nonReentrant {
        _validateFarmOpen();
        if (farmStartTime > block.timestamp) {
            revert FarmNotYetStarted();
        }
        if (_extensionDays < MIN_EXTENSION || _extensionDays > MAX_EXTENSION) {
            revert InvalidExtension();
        }

        uint256 newFarmEndTime = farmEndTime + _extensionDays * 1 days;
        if (newFarmEndTime > block.timestamp + MAX_EXTENSION * 1 days) {
            revert DurationExceeded();
        }

        farmEndTime = newFarmEndTime;
        _collectExtensionFee(_extensionDays);

        emit FarmEndTimeUpdated(newFarmEndTime);
    }

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start.
    ///      New start time should be in future.
    ///      Adjusts the farm end time accordingly.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) public virtual override {
        uint256 currentFarmStartTime = farmStartTime;

        super.updateFarmStartTime(_newStartTime);

        uint256 _farmEndTime = farmEndTime;
        _farmEndTime = (_newStartTime > currentFarmStartTime)
            ? _farmEndTime + (_newStartTime - currentFarmStartTime)
            : _farmEndTime - (currentFarmStartTime - _newStartTime);

        farmEndTime = _farmEndTime;

        emit FarmEndTimeUpdated(_farmEndTime);
    }

    /// @notice Returns bool status if farm is open.
    ///         Farm is open if it is not closed and not expired.
    /// @return bool True if farm is open.
    function isFarmOpen() public view virtual override returns (bool) {
        return super.isFarmOpen() && (block.timestamp <= farmEndTime);
    }

    /// @notice Setup the farm data for farm expiry.
    /// @param _farmStartTime Start time of the farm.
    /// @param _farmRegistry Address of the farm registry.
    function _setupFarmExpiry(uint256 _farmStartTime, address _farmRegistry) internal {
        _validateNonZeroAddr(_farmRegistry);
        farmEndTime = _farmStartTime + MIN_EXTENSION * 1 days;
        farmRegistry = _farmRegistry;
    }

    // --------------------- Private  Functions ---------------------

    /// @notice Collects farm extension fee and transfers it to feeReceiver.
    /// @dev Function fetches all the fee params from farmRegistry.
    /// @param _extensionDays The number of days to extend the farm. Example: 150 means 150 days.
    function _collectExtensionFee(uint256 _extensionDays) private {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list.
        (address feeReceiver, address feeToken,, uint256 extensionFeePerDay) =
            IFarmRegistry(farmRegistry).getFeeParams(msg.sender);
        if (extensionFeePerDay != 0) {
            uint256 extensionFeeAmount = _extensionDays * extensionFeePerDay;
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, extensionFeeAmount);
            emit ExtensionFeeCollected(feeToken, extensionFeeAmount);
        }
    }
}
