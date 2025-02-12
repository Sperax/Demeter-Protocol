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

import {E20Farm} from "../E20Farm.sol";
import {Farm, RewardTokenData} from "../../Farm.sol";
import {ExpirableFarm} from "./../../features/ExpirableFarm.sol";

/// @title Balancer V2 farm.
/// @author Sperax Foundation.
/// @notice This contract is the implementation of the Balancer V2 farm.
contract BalancerV2Farm is E20Farm, ExpirableFarm {
    error NotImplemented();

    /// @notice Constructor.
    /// @param _farmId - ID of the farm.
    /// @param _farmStartTime - Farm start time.
    /// @param _cooldownPeriod - Cooldown period for locked deposits in days.
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _farmRegistry - Address of the Demeter Farm Registry.
    /// @param _farmToken Address of the farm token.
    /// @param _rwdTokenData - Initialize data for reward tokens.
    function initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _farmRegistry,
        address _farmToken,
        RewardTokenData[] memory _rwdTokenData
    ) external {
        super._initialize({
            _farmId: _farmId,
            _farmStartTime: _farmStartTime,
            _cooldownPeriod: _cooldownPeriod,
            _farmToken: _farmToken,
            _rwdTokenData: _rwdTokenData
        });
        _setupFarmExpiry(_farmStartTime, _farmRegistry);
    }

    /// @notice Function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    /// @dev This function is not implemented in this contract.
    function getTokenAmounts() external view virtual override returns (address[] memory, uint256[] memory) {
        revert NotImplemented();
    }

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start.
    ///      New start time should be in future.
    ///      Adjusts the farm end time accordingly.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) public override(ExpirableFarm, Farm) {
        ExpirableFarm.updateFarmStartTime(_newStartTime);
    }

    /// @notice Returns bool status if farm is open.
    ///         Farm is open if it is not closed and not expired.
    /// @return bool True if farm is open.
    function isFarmOpen() public view override(ExpirableFarm, Farm) returns (bool) {
        return ExpirableFarm.isFarmOpen();
    }

    /// @notice Recover erc20 tokens other than the reward Tokens and farm token.
    /// @param _token Address of token to be recovered.
    function _recoverERC20(address _token) internal override(E20Farm, Farm) {
        E20Farm._recoverERC20(_token);
    }
}
