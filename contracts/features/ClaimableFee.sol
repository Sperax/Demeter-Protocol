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

import {Farm} from "./../Farm.sol";

/// @title Claimable pool fee feature contract of Sperax Demeter protocol.
/// @author Sperax Foundation.
/// @notice Farms build for pairs/ pools in which fee can be claimed can extend and override _claimPoolFee function of this contract.
abstract contract ClaimableFee is Farm {
    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    error NoFeeToClaim();

    /// @notice A function to claim the pool fee earned by lp.
    /// @dev Only the deposit owner can call this function.
    /// @param _depositId ID of the deposit.
    function claimPoolFee(uint256 _depositId) external nonReentrant {
        _validateFarmOpen();
        _validateDeposit(msg.sender, _depositId);

        (uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv) = _claimPoolFee(_depositId);

        if (amt0Recv == 0 && amt1Recv == 0) {
            revert NoFeeToClaim();
        }

        emit PoolFeeCollected(msg.sender, tokenId, amt0Recv, amt1Recv);
    }

    /// @notice Claim pool fee internal logic to be implemented by child farm contract.
    /// @param _depositId Deposit ID of the deposit in the farm.
    /// @dev Just override this function and write the logic to claim fee, validation and other checks are handled in `claimPoolFee`.
    /// @return tokenId Token ID of the deposit for E721 farms, for other farms return depositId.
    /// @return amt0Recv Amount 0 received as fee.
    /// @return amt1Recv Amount 1 received as fee.
    function _claimPoolFee(uint256 _depositId)
        internal
        virtual
        returns (uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);
}
