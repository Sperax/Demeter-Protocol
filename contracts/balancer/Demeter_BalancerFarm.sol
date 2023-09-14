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

contract Demeter_BalancerFarm is BaseFarm {
    using SafeERC20 for IERC20;

    // Token params
    address public farmToken;
    uint256 public tokenNum;

    event PoolFeeCollected(
        address indexed recipient,
        uint256 amt0Recv,
        uint256 amt1Recv
    );

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
        // Initialize farm global params
        tokenNum = 0;

        // initialize farmToken related data
        farmToken = _farmToken;
        _setupFarm(_farmStartTime, _cooldownPeriod, _rwdTokenData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _amount Amount of farmToken to be deposited
    /// @param _lockup The lockup flag (bool).
    function deposit(uint256 _amount, bool _lockup) external nonReentrant {
        address account = msg.sender;
        uint256 tokenId = ++tokenNum;
        // Execute common deposit logic.
        _deposit(account, _lockup, tokenId, _amount);

        // Transfer the lp tokens to the farm
        IERC20(farmToken).safeTransferFrom(account, address(this), _amount);
    }

    /// @notice Allow user to increase liquidity for a deposit
    /// @param _depositId Deposit index for the user.
    /// @param _amount Desired amount
    /// @dev User cannot increase liquidity for a deposit in cooldown
    function increaseDeposit(uint8 _depositId, uint256 _amount)
        external
        nonReentrant
    {
        address account = msg.sender;
        // Validations
        _farmNotClosed();
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];
        require(_amount > 0, "Invalid amount");
        require(userDeposit.expiryDate == 0, "Deposit in cooldown");

        // claim the pending rewards for the deposit
        _claimRewards(account, _depositId);

        // Update deposit Information
        _updateSubscriptionForIncrease(userDeposit.tokenId, _amount);
        deposits[account][_depositId].liquidity += _amount;

        // Transfer the lp tokens to the farm
        IERC20(farmToken).safeTransferFrom(account, address(this), _amount);
    }

    /// @notice Withdraw liquidity partially from an existing deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _amount Amount to be withdrawn.
    /// @dev Function is not available for locked deposits.
    function withdrawPartially(uint8 _depositId, uint256 _amount)
        external
        nonReentrant
    {
        address account = msg.sender;
        //Validations
        _farmNotClosed();
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];
        require(
            _amount > 0 && _amount < userDeposit.liquidity,
            "Invalid amount"
        );
        require(
            userDeposit.expiryDate == 0 && userDeposit.cooldownPeriod == 0,
            "Partial withdraw not permitted"
        );

        // claim the pending rewards for the deposit
        _claimRewards(account, _depositId);

        // Update deposit info
        _updateSubscriptionForDecrease(userDeposit.tokenId, _amount);
        deposits[account][_depositId].liquidity -= _amount;

        // Transfer the lp tokens to the user
        IERC20(farmToken).safeTransfer(account, _amount);
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
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];

        _withdraw(account, _depositId, userDeposit);

        // Transfer the farmTokens to the user.
        IERC20(farmToken).safeTransfer(account, userDeposit.liquidity);
    }

    /// @notice Update subscription data of a deposit for increase in liquidity.
    /// @param _tokenId Unique token id for the deposit
    /// @param _amount Amount to be increased.
    function _updateSubscriptionForIncrease(uint256 _tokenId, uint256 _amount)
        private
    {
        Subscription[] storage depositSubs = subscriptions[_tokenId];
        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        for (uint256 iSub = 0; iSub < numSubs; ) {
            for (uint8 iRwd = 0; iRwd < numRewards; ) {
                depositSubs[iSub].rewardDebt[iRwd] += ((_amount *
                    rewardFunds[depositSubs[iSub].fundId].accRewardPerShare[
                        iRwd
                    ]) / PREC);
                unchecked {
                    ++iRwd;
                }
            }
            rewardFunds[depositSubs[iSub].fundId].totalLiquidity += _amount;
            unchecked {
                ++iSub;
            }
        }
    }

    /// @notice Update subscription data of a deposit after decrease in liquidity.
    /// @param _tokenId Unique token id for the deposit
    /// @param _amount Amount to be increased.
    function _updateSubscriptionForDecrease(uint256 _tokenId, uint256 _amount)
        private
    {
        Subscription[] storage depositSubs = subscriptions[_tokenId];
        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        for (uint256 iSub = 0; iSub < numSubs; ) {
            for (uint8 iRwd = 0; iRwd < numRewards; ) {
                depositSubs[iSub].rewardDebt[iRwd] -= ((_amount *
                    rewardFunds[depositSubs[iSub].fundId].accRewardPerShare[
                        iRwd
                    ]) / PREC);
                unchecked {
                    ++iRwd;
                }
            }
            rewardFunds[depositSubs[iSub].fundId].totalLiquidity -= _amount;
            unchecked {
                ++iSub;
            }
        }
    }
}