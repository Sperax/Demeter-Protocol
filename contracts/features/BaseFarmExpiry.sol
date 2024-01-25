// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseFarm, RewardTokenData} from "../BaseFarm.sol";
import {IFarmFactory} from "../interfaces/IFarmFactory.sol";

abstract contract BaseFarmExpiry is BaseFarm {
    using SafeERC20 for IERC20;

    uint256 public constant INITIAL_FARM_EXTENSION = 100 days;
    uint256 public farmEndTime;

    event FarmEndTimeUpdated(uint256 newEndTime);
    event ExtensionFeeCollected(address token, uint256 extensionFee);

    error InvalidExtension();
    error FarmHasExpired();

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start
    ///      New start time should be in future.
    ///      Adjusts the farm end time accordingly.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) public override onlyOwner {
        uint256 _currentLastFundUpdateTime = lastFundUpdateTime;

        super.updateFarmStartTime(_newStartTime);

        farmEndTime = (_newStartTime > _currentLastFundUpdateTime)
            ? farmEndTime + (_newStartTime - _currentLastFundUpdateTime)
            : farmEndTime - (_currentLastFundUpdateTime - _newStartTime);
    }

    /// @notice Update the farm end time.
    /// @dev Can be updated only before the farm expired or closed
    ///      extension should be incremented in multiples of 1 USDs/day with minimum of 100 days at a time and a maximum of 300 days
    ///      extension is possible only after farm started
    /// @param _extensionDays The number of days to extend the farm
    function extendFarmDuration(uint256 _extensionDays) external onlyOwner nonReentrant {
        _isFarmActive();
        if (lastFundUpdateTime > block.timestamp) {
            revert FarmNotYetStarted();
        }
        if (_extensionDays < 100 || _extensionDays > 300) {
            revert InvalidExtension();
        }

        uint256 newFarmEndTime = farmEndTime + _extensionDays * 1 days;
        farmEndTime = newFarmEndTime;

        _collectExtensionFee(_extensionDays);

        emit FarmEndTimeUpdated(newFarmEndTime);
    }

    /// @notice Validate if farm is not closed or expired
    function _isFarmActive() internal view override {
        super._isFarmActive();
        if (block.timestamp > farmEndTime) {
            revert FarmHasExpired();
        }
    }

    /// @notice Setup the farm data
    function _setupFarm(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        RewardTokenData[] memory _rwdTokenData,
        address _farmFactory
    ) internal override {
        super._setupFarm(_farmStartTime, _cooldownPeriod, _rwdTokenData, _farmFactory);
        farmEndTime = _farmStartTime + INITIAL_FARM_EXTENSION;
    }

    /// @notice Validate if farm is not expired
    /// @return bool true if farm is not expired
    function _isFarmNotExpired() internal view override returns (bool) {
        return (block.timestamp <= farmEndTime);
    }

    /// @notice Collect farm extension fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
    function _collectExtensionFee(uint256 _extensionDays) private {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list
        (address feeReceiver, address feeToken,, uint256 extensionFeePerDay) =
            IFarmFactory(farmFactory).getFeeParams(msg.sender);
        if (extensionFeePerDay != 0) {
            uint256 extensionFeeAmount = _extensionDays * extensionFeePerDay;
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, extensionFeeAmount);
            emit ExtensionFeeCollected(feeToken, extensionFeeAmount);
        }
    }
}
