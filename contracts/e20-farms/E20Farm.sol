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
import {RewardTokenData} from "../Farm.sol";
import {OperableDeposit} from "../features/OperableDeposit.sol";

/// @title  Base E20Farm contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract contains the core logic for E20 farms.
abstract contract E20Farm is OperableDeposit {
    using SafeERC20 for IERC20;

    // Token params.
    address public farmToken;

    // Events.
    event PoolFeeCollected(address indexed recipient, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors.
    error InvalidAmount();
    error CannotWithdrawFarmToken();

    /// @notice Function to deposit farm tokens into the farm.
    /// @param _amount Amount of farmToken to be deposited.
    /// @param _lockup The lockup flag (bool).
    function deposit(uint256 _amount, bool _lockup) external nonReentrant {
        // Execute common deposit logic.
        _deposit(msg.sender, _lockup, _amount);

        // Transfer the lp tokens to the farm.
        IERC20(farmToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Allow user to increase liquidity for a deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _amount Desired amount.
    /// @dev User cannot increase liquidity for a deposit in cooldown.
    function increaseDeposit(uint256 _depositId, uint256 _amount) external nonReentrant {
        _validateDeposit(msg.sender, _depositId);
        if (_amount == 0) {
            revert InvalidAmount();
        }

        _increaseDeposit(_depositId, _amount);

        // Transfer the lp tokens to the farm.
        IERC20(farmToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Withdraw liquidity partially from an existing deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _amount Amount to be withdrawn.
    /// @dev Function is not available for locked deposits.
    function decreaseDeposit(uint256 _depositId, uint256 _amount) external nonReentrant {
        _decreaseDeposit(_depositId, _amount);

        // Transfer the lp tokens to the user.
        IERC20(farmToken).safeTransfer(msg.sender, _amount);
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn.
    function withdraw(uint256 _depositId) external override nonReentrant {
        uint256 liquidity = deposits[_depositId].liquidity;
        _withdraw(_depositId);

        // Transfer the farmTokens to the user.
        IERC20(farmToken).safeTransfer(msg.sender, liquidity);
    }

    /// @notice Constructor.
    /// @param _farmStartTime - Farm start time.
    /// @param _cooldownPeriod - Cooldown period for locked deposits in days.
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _farmToken Address of the farm token.
    /// @param _rwdTokenData - Initialize data for reward tokens.
    function _initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _farmToken,
        RewardTokenData[] memory _rwdTokenData
    ) internal {
        // initialize farmToken related data.
        farmToken = _farmToken;
        _setupFarm(_farmId, _farmStartTime, _cooldownPeriod, _rwdTokenData);
    }

    /// @notice Recover erc20 tokens other than the reward Tokens and farm token.
    /// @param _token Address of token to be recovered.
    function _recoverERC20(address _token) internal virtual override {
        if (_token == farmToken) revert CannotWithdrawFarmToken();
        super._recoverERC20(_token);
    }
}
