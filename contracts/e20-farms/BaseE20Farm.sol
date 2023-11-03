// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@&....(@@@@@@@@@@@@@..../@@@@@@@@@//
//@@@@@@........../@@@@@@@........../@@@@@@//
//@@@@@............(@@@@@............(@@@@@//
//@@@@@(............@@@@@(...........&@@@@@//
//@@@@@@@...........&@@@@@@.........@@@@@@@//
//@@@@@@@@@@@@@@%..../@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@...@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@......(&@@@@@@@@@@@@//
//@@@@@@#.........@@@@@@#...........@@@@@@@//
//@@@@@/...........%@@@@@............%@@@@@//
//@@@@@............#@@@@@............%@@@@@//
//@@@@@@..........#@@@@@@@/.........#@@@@@@//
//@@@@@@@@@&/.(@@@@@@@@@@@@@@&/.(&@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseFarm.sol";

contract BaseE20Farm is BaseFarm {
    using SafeERC20 for IERC20;

    // Token params
    address public farmToken;
    uint256 public tokenNum;

    event PoolFeeCollected(address indexed recipient, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidAmount();
    error DepositInCooldown();
    error PartialWithdrawNotPermitted();
    error CannotWithdrawRewardTokenOrFarmToken();

    /// @notice constructor
    /// @param _farmStartTime - time of farm start
    /// @param _cooldownPeriod - cooldown period for locked deposits in days
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _farmToken Address of the farm token
    /// @param _rwdTokenData - init data for reward tokens
    function initialize(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _farmToken,
        RewardTokenData[] memory _rwdTokenData
    ) external initializer {
        // initialize farmToken related data
        farmToken = _farmToken;
        _setupFarm(_farmStartTime, _cooldownPeriod, _rwdTokenData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _amount Amount of farmToken to be deposited
    /// @param _lockup The lockup flag (bool).
    function deposit(uint256 _amount, bool _lockup) external nonReentrant {
        // Execute common deposit logic.
        _deposit(msg.sender, _lockup, ++tokenNum, _amount);

        // Transfer the lp tokens to the farm
        IERC20(farmToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Allow user to increase liquidity for a deposit
    /// @param _depositId Deposit index for the user.
    /// @param _amount Desired amount
    /// @dev User cannot increase liquidity for a deposit in cooldown
    function increaseDeposit(uint8 _depositId, uint256 _amount) external nonReentrant {
        // Validations
        _farmNotClosed();
        _isValidDeposit(msg.sender, _depositId);
        Deposit memory userDeposit = deposits[msg.sender][_depositId];
        if (_amount == 0) {
            revert InvalidAmount();
        }
        if (userDeposit.expiryDate != 0) {
            revert DepositInCooldown();
        }

        // claim the pending rewards for the deposit
        _claimRewards(msg.sender, _depositId);

        // Update deposit Information
        _updateSubscriptionForIncrease(userDeposit.tokenId, _amount);
        deposits[msg.sender][_depositId].liquidity += _amount;

        // Transfer the lp tokens to the farm
        IERC20(farmToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Withdraw liquidity partially from an existing deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _amount Amount to be withdrawn.
    /// @dev Function is not available for locked deposits.
    function withdrawPartially(uint8 _depositId, uint256 _amount) external nonReentrant {
        //Validations
        _farmNotClosed();
        _isValidDeposit(msg.sender, _depositId);
        Deposit storage userDeposit = deposits[msg.sender][_depositId];

        if (_amount == 0 || _amount >= userDeposit.liquidity) {
            revert InvalidAmount();
        }

        if (userDeposit.expiryDate != 0 || userDeposit.cooldownPeriod != 0) {
            revert PartialWithdrawNotPermitted();
        }

        // claim the pending rewards for the deposit
        _claimRewards(msg.sender, _depositId);

        // Update deposit info
        _updateSubscriptionForDecrease(userDeposit.tokenId, _amount);
        userDeposit.liquidity -= _amount;

        // Transfer the lp tokens to the user
        IERC20(farmToken).safeTransfer(msg.sender, _amount);
    }

    /// @notice Function to lock a staked deposit
    /// @param _depositId The id of the deposit to be locked
    /// @dev _depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 _depositId) external nonReentrant {
        _initiateCooldown(_depositId);
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external nonReentrant {
        _isValidDeposit(msg.sender, _depositId);
        Deposit memory userDeposit = deposits[msg.sender][_depositId];

        _withdraw(msg.sender, _depositId, userDeposit);

        // Transfer the farmTokens to the user.
        IERC20(farmToken).safeTransfer(msg.sender, userDeposit.liquidity);
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Recover erc20 tokens other than the reward Tokens and farm token.
    /// @param _token Address of token to be recovered
    function recoverERC20(address _token) external override onlyOwner nonReentrant {
        if (rewardData[_token].tknManager != address(0) || _token == farmToken) {
            revert CannotWithdrawRewardTokenOrFarmToken();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert CannotWithdrawZeroAmount();
        }

        IERC20(_token).safeTransfer(owner(), balance);
        emit RecoveredERC20(_token, balance);
    }

    // --------------------- Private  Functions ---------------------

    /// @notice Update subscription data of a deposit for increase in liquidity.
    /// @param _tokenId Unique token id for the deposit
    /// @param _amount Amount to be increased.
    function _updateSubscriptionForIncrease(uint256 _tokenId, uint256 _amount) private {
        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = subscriptions[_tokenId].length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = subscriptions[_tokenId][iSub].rewardDebt;
            uint8 _fundId = subscriptions[_tokenId][iSub].fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
                _rewardDebt[iRwd] += ((_amount * rewardFunds[_fundId].accRewardPerShare[iRwd]) / PREC);
                unchecked {
                    ++iRwd;
                }
            }
            rewardFunds[_fundId].totalLiquidity += _amount;
            unchecked {
                ++iSub;
            }
        }
    }

    /// @notice Update subscription data of a deposit after decrease in liquidity.
    /// @param _tokenId Unique token id for the deposit
    /// @param _amount Amount to be increased.
    function _updateSubscriptionForDecrease(uint256 _tokenId, uint256 _amount) private {
        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = subscriptions[_tokenId].length;
        for (uint256 iSub; iSub < numSubs;) {
            uint256[] storage _rewardDebt = subscriptions[_tokenId][iSub].rewardDebt;
            uint8 _fundId = subscriptions[_tokenId][iSub].fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
                _rewardDebt[iRwd] -= ((_amount * rewardFunds[_fundId].accRewardPerShare[iRwd]) / PREC);
                unchecked {
                    ++iRwd;
                }
            }
            rewardFunds[_fundId].totalLiquidity -= _amount;
            unchecked {
                ++iSub;
            }
        }
    }
}
