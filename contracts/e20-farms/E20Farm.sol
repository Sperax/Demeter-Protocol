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
import {RewardTokenData} from "../Farm.sol";
import {ExpirableFarm} from "../features/ExpirableFarm.sol";
import {OperableDeposit} from "../features/OperableDeposit.sol";

/// @title  Base E20Farm contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract contains the core logic for E20 farms.
abstract contract E20Farm is ExpirableFarm, OperableDeposit {
    using SafeERC20 for IERC20;

    // Token params.
    address public farmToken;

    event PoolFeeCollected(address indexed recipient, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors.
    error InvalidAmount();
    error CannotWithdrawFarmToken();

    /// @notice constructor.
    /// @param _farmStartTime - farm start time.
    /// @param _cooldownPeriod - cooldown period for locked deposits in days.
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _farmRegistry - Address of the Demeter Farm Registry.
    /// @param _farmToken Address of the farm token.
    /// @param _rwdTokenData - init data for reward tokens.
    function initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _farmRegistry,
        address _farmToken,
        RewardTokenData[] memory _rwdTokenData
    ) external initializer {
        // initialize farmToken related data.
        farmToken = _farmToken;
        _setupFarm(_farmId, _farmStartTime, _cooldownPeriod, _rwdTokenData);
        _setupFarmExpiry(_farmStartTime, _farmRegistry);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
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
        _withdraw(msg.sender, _depositId);

        // Transfer the farmTokens to the user.
        IERC20(farmToken).safeTransfer(msg.sender, liquidity);
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Recover erc20 tokens other than the reward Tokens and farm token.
    /// @param _token Address of token to be recovered.
    function recoverERC20(address _token) external override onlyOwner nonReentrant {
        if (_token == farmToken) revert CannotWithdrawFarmToken();
        _recoverE20(_token);
    }
}
