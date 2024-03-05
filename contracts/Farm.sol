// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

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
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {FarmStorage} from "./FarmStorage.sol";
import {RewardTokenData, RewardFund, Subscription, Deposit, RewardData} from "./interfaces/DataTypes.sol";

abstract contract Farm is FarmStorage, Ownable, ReentrancyGuard, Initializable, Multicall {
    using SafeERC20 for IERC20;

    event Deposited(uint256 indexed depositId, address indexed account, bool locked, uint256 liquidity);
    event CooldownInitiated(uint256 indexed depositId, uint256 expiryDate);
    event DepositWithdrawn(uint256 indexed depositId);
    event RewardsClaimed(uint256 indexed depositId, uint256[][] rewardsForEachSubs);
    event PoolUnsubscribed(uint256 indexed depositId, uint8 fundId, uint256[] totalRewardsClaimed);
    event PoolSubscribed(uint256 indexed depositId, uint8 fundId);
    event FarmStartTimeUpdated(uint256 newStartTime);
    event CooldownPeriodUpdated(uint256 newCooldownPeriod);
    event RewardRateUpdated(address indexed rwdToken, uint256[] newRewardRate);
    event RewardAdded(address rwdToken, uint256 amount);
    event FarmClosed();
    event RecoveredERC20(address token, uint256 amount);
    event FundsRecovered(address indexed account, address indexed rwdToken, uint256 amount);
    event RewardDataUpdated(address indexed rwdToken, address newTokenManager);
    event RewardTokenAdded(address indexed rwdToken, address rwdTokenManager);
    event FarmPaused(bool paused);

    // Custom Errors
    error InvalidRewardToken();
    error FarmDoesNotSupportLockup();
    error FarmAlreadyStarted();
    error InvalidTime();
    error FarmAlreadyInRequiredState();
    error CannotWithdrawRewardToken();
    error CannotWithdrawZeroAmount();
    error SubscriptionDoesNotExist();
    error RewardFundDoesNotExist();
    error LockupFunctionalityIsDisabled();
    error NoLiquidityInPosition();
    error CannotInitiateCooldown();
    error PleaseInitiateCooldown();
    error DepositIsInCooldown();
    error InvalidRewardRatesLength();
    error InvalidFundId();
    error InvalidFarmStartTime();
    error InvalidRewardData();
    error RewardTokenAlreadyAdded();
    error DepositDoesNotExist();
    error FarmIsClosed();
    error FarmIsInactive();
    error NotTheTokenManager();
    error InvalidAddress();
    error ZeroAmount();
    error InvalidCooldownPeriod();
    error NotImplemented();

    // Disallow initialization of a implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice A function to be called to withdraw deposit.
    /// @param _depositId Id of the deposit.
    function withdraw(uint256 _depositId) external virtual;

    /// @notice Claim rewards for the user.
    /// @param _depositId The id of the deposit.
    function claimRewards(uint256 _depositId) external {
        claimRewards(msg.sender, _depositId);
    }

    /// @notice Function to be called to initiate cooldown for a staked deposit.
    /// @param _depositId The id of the deposit to be locked.
    /// @dev _depositId is corresponding to the user's deposit.
    function initiateCooldown(uint256 _depositId) external nonReentrant {
        _initiateCooldown(_depositId);
    }

    /// @notice Add rewards to the farm.
    /// @param _rwdToken the reward token's address.
    /// @param _amount the amount of reward tokens to add.
    function addRewards(address _rwdToken, uint256 _amount) external nonReentrant {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        _validateFarmOpen();
        if (rewardData[_rwdToken].tknManager == address(0)) {
            revert InvalidRewardToken();
        }
        _updateFarmRewardData();
        IERC20(_rwdToken).safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardAdded(_rwdToken, _amount);
    }

    // --------------------- Admin  Functions ---------------------

    /// @notice Update the cooldown period.
    /// @param _newCooldownPeriod The new cooldown period (in days). Egs: 7 means 7 days.
    function updateCooldownPeriod(uint256 _newCooldownPeriod) external onlyOwner {
        _validateFarmOpen();
        if (cooldownPeriod == 0) {
            revert FarmDoesNotSupportLockup();
        }
        _validateCooldownPeriod(_newCooldownPeriod);
        cooldownPeriod = _newCooldownPeriod * 1 days;
        emit CooldownPeriodUpdated(_newCooldownPeriod);
    }

    /// @notice Pause / UnPause the farm.
    /// @param _isPaused Desired state of the farm (true to pause the farm).
    function farmPauseSwitch(bool _isPaused) external onlyOwner {
        _validateFarmOpen();
        if (isPaused == _isPaused) {
            revert FarmAlreadyInRequiredState();
        }
        _updateFarmRewardData();
        isPaused = _isPaused;
        emit FarmPaused(isPaused);
    }

    /// @notice Recover rewardToken from the farm in case of EMERGENCY.
    /// @dev Shuts down the farm completely.
    function closeFarm() external onlyOwner nonReentrant {
        _validateFarmOpen();
        _updateFarmRewardData();
        isPaused = true;
        isClosed = true;
        uint256 numRewards = rewardTokens.length;
        for (uint8 iRwd; iRwd < numRewards;) {
            _recoverRewardFunds(rewardTokens[iRwd], type(uint256).max);
            _setRewardRate(rewardTokens[iRwd], new uint256[](rewardFunds.length));
            unchecked {
                ++iRwd;
            }
        }
        emit FarmClosed();
    }

    /// @notice Recover erc20 tokens other than the reward Tokens.
    /// @param _token Address of token to be recovered.
    function recoverERC20(address _token) external virtual onlyOwner nonReentrant {
        _recoverE20(_token);
    }

    // --------------------- Token Manager Functions ---------------------
    /// @notice Get the remaining balance out of the farm.
    /// @param _rwdToken The reward token's address.
    /// @param _amount The amount of the reward tokens to be withdrawn.
    /// @dev Function recovers minOf(_amount, rewardsLeft).
    function recoverRewardFunds(address _rwdToken, uint256 _amount) external nonReentrant {
        _validateTokenManager(_rwdToken);
        _updateFarmRewardData();
        _recoverRewardFunds(_rwdToken, _amount);
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address.
    /// @param _newRewardRates The new reward rate for the fund (includes the precision).
    function setRewardRate(address _rwdToken, uint256[] memory _newRewardRates) external {
        _validateFarmOpen();
        _validateTokenManager(_rwdToken);
        _updateFarmRewardData();
        _setRewardRate(_rwdToken, _newRewardRates);
    }

    /// @notice Transfer the tokenManagerRole to other user.
    /// @dev Only the existing tokenManager for a reward can call this function.
    /// @param _rwdToken The reward token's address.
    /// @param _newTknManager Address of the new token manager.
    function updateRewardData(address _rwdToken, address _newTknManager) external {
        _validateFarmOpen();
        _validateTokenManager(_rwdToken);
        _validateNonZeroAddr(_newTknManager);
        rewardData[_rwdToken].tknManager = _newTknManager;
        emit RewardDataUpdated(_rwdToken, _newTknManager);
    }

    /// @notice Function to compute the total accrued rewards for a deposit for each subscription.
    /// @param _account The user's address.
    /// @param _depositId The id of the deposit.
    /// @return rewards The total accrued rewards for the deposit for each subscription (uint256[][]).
    function computeRewards(address _account, uint256 _depositId)
        external
        view
        virtual
        returns (uint256[][] memory rewards)
    {
        _validateDeposit(_account, _depositId);
        uint256 userLiquidity = deposits[_depositId].liquidity;
        Subscription[] storage depositSubs = subscriptions[_depositId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numDepositSubs = depositSubs.length;
        uint256 numRewards = rewardTokens.length;
        rewards = new uint256[][](numDepositSubs);

        uint256 time = _getRewardAccrualTimeElapsed();

        // Update the two reward funds.
        for (uint8 iSub; iSub < numDepositSubs;) {
            Subscription storage sub = depositSubs[iSub];
            rewards[iSub] = new uint256[](numRewards);
            uint8 fundId = sub.fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
                if (funds[fundId].totalLiquidity != 0 && isFarmActive()) {
                    uint256 accRewards = _getAccRewards(iRwd, fundId, time);
                    // update the accRewardPerShare for delta time.
                    funds[fundId].accRewardPerShare[iRwd] += (accRewards * PREC) / funds[fundId].totalLiquidity;
                }
                rewards[iSub][iRwd] =
                    ((userLiquidity * funds[fundId].accRewardPerShare[iRwd]) / PREC) - sub.rewardDebt[iRwd];
                unchecked {
                    ++iRwd;
                }
            }
            unchecked {
                ++iSub;
            }
        }
        return rewards;
    }

    /// @notice Get deposit info for a deposit id
    /// @param _depositId The id of the deposit
    function getDepositInfo(uint256 _depositId) external view returns (Deposit memory) {
        if (_depositId == 0 || _depositId > totalDeposits) {
            revert DepositDoesNotExist();
        }
        return deposits[_depositId];
    }

    /// @notice Get number of subscriptions for an account.
    /// @param _depositId The deposit id.
    function getNumSubscriptions(uint256 _depositId) external view returns (uint256) {
        return subscriptions[_depositId].length;
    }

    /// @notice Get subscription stats for a deposit.
    /// @param _depositId The deposit id.
    /// @param _subscriptionId The subscription's id.
    function getSubscriptionInfo(uint256 _depositId, uint256 _subscriptionId)
        external
        view
        returns (Subscription memory)
    {
        if (_subscriptionId >= subscriptions[_depositId].length) {
            revert SubscriptionDoesNotExist();
        }
        return subscriptions[_depositId][_subscriptionId];
    }

    /// @notice Get reward rates for a rewardToken.
    /// @param _rwdToken The reward token's address.
    /// @return The reward rates for the reward token (uint256[]).
    function getRewardRates(address _rwdToken) external view returns (uint256[] memory) {
        uint256 numFunds = rewardFunds.length;
        uint256[] memory rates = new uint256[](numFunds);
        uint8 id = rewardData[_rwdToken].id;
        for (uint8 iFund; iFund < numFunds;) {
            rates[iFund] = rewardFunds[iFund].rewardsPerSec[id];
            unchecked {
                ++iFund;
            }
        }
        return rates;
    }

    /// @notice Get farm reward fund info.
    /// @param _fundId The fund's id.
    function getRewardFundInfo(uint8 _fundId) external view returns (RewardFund memory) {
        if (_fundId >= rewardFunds.length) {
            revert RewardFundDoesNotExist();
        }
        return rewardFunds[_fundId];
    }

    /// @notice A function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    function getTokenAmounts() external view virtual returns (address[] memory, uint256[] memory);

    /// @notice Claim rewards for the user.
    /// @param _account The user's address.
    /// @param _depositId The id of the deposit.
    /// @dev Anyone can call this function to claim rewards for the user.
    function claimRewards(address _account, uint256 _depositId) public nonReentrant {
        _validateFarmOpen();
        _validateDeposit(_account, _depositId);
        _updateAndClaimFarmRewards(_account, _depositId);
    }

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start
    ///      New start time should be in future.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) public virtual onlyOwner {
        _validateFarmOpen();
        if (lastFundUpdateTime <= block.timestamp) {
            revert FarmAlreadyStarted();
        }
        if (_newStartTime < block.timestamp) {
            revert InvalidTime();
        }

        lastFundUpdateTime = _newStartTime;

        emit FarmStartTimeUpdated(_newStartTime);
    }

    /// @notice Returns if farm is open.
    ///         Farm is open if it not closed.
    /// @return bool true if farm is open.
    /// @dev This function can be overridden to add any new/additional logic.
    function isFarmOpen() public view virtual returns (bool) {
        return !isClosed;
    }

    /// @notice Returns if farm is active.
    ///         Farm is active if it is not paused and not closed.
    /// @return bool true if farm is active.
    /// @dev This function can be overridden to add any new/additional logic.
    function isFarmActive() public view virtual returns (bool) {
        return !isPaused && isFarmOpen();
    }

    /// @notice Get the reward balance for specified reward token.
    /// @param _rwdToken The address of the reward token.
    /// @return The available reward balance for the specified reward token.
    /// @dev This function calculates the available reward balance by considering the accrued rewards and the token supply.
    function getRewardBalance(address _rwdToken) public view returns (uint256) {
        RewardData memory rwdData = rewardData[_rwdToken];

        if (rwdData.tknManager == address(0)) {
            revert InvalidRewardToken();
        }

        uint256 numFunds = rewardFunds.length;
        uint256 rewardsAcc = rwdData.accRewardBal;
        uint256 supply = IERC20(_rwdToken).balanceOf(address(this));
        if (block.timestamp > lastFundUpdateTime) {
            uint256 time;
            unchecked {
                time = block.timestamp - lastFundUpdateTime;
            }
            // Compute the accrued reward balance for time
            for (uint8 iFund; iFund < numFunds;) {
                if (rewardFunds[iFund].totalLiquidity != 0) {
                    rewardsAcc += rewardFunds[iFund].rewardsPerSec[rwdData.id] * time;
                }
                unchecked {
                    ++iFund;
                }
            }
        }
        if (rewardsAcc >= supply) {
            return 0;
        }
        return (supply - rewardsAcc);
    }

    function _recoverE20(address _token) internal {
        if (rewardData[_token].tknManager != address(0)) {
            revert CannotWithdrawRewardToken();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert CannotWithdrawZeroAmount();
        }

        IERC20(_token).safeTransfer(msg.sender, balance);
        emit RecoveredERC20(_token, balance);
    }

    /// @notice Common logic for deposit in the demeter farm.
    /// @param _account Address of the depositor.
    /// @param _lockup Lockup option for the deposit.
    /// @param _liquidity Liquidity amount to be added to the pool.
    function _deposit(address _account, bool _lockup, uint256 _liquidity) internal returns (uint256) {
        // Allow deposit only when farm is not paused and not closed.
        _validateFarmActive();

        if (cooldownPeriod == 0) {
            if (_lockup) {
                revert LockupFunctionalityIsDisabled();
            }
        }

        if (_liquidity == 0) {
            revert NoLiquidityInPosition();
        }
        // Update the reward funds.
        _updateFarmRewardData();

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            depositor: _account,
            cooldownPeriod: 0,
            startTime: block.timestamp,
            expiryDate: 0,
            totalRewardsClaimed: new uint256[](rewardTokens.length),
            liquidity: _liquidity
        });

        // @dev Pre increment because we want deposit IDs to start with 1.
        uint256 currentDepositId = ++totalDeposits;

        // Add common fund subscription to the user's deposit.
        _subscribeRewardFund(COMMON_FUND_ID, currentDepositId, _liquidity);

        if (_lockup) {
            // Add lockup fund subscription to the user's deposit.
            userDeposit.cooldownPeriod = cooldownPeriod;
            _subscribeRewardFund(LOCKUP_FUND_ID, currentDepositId, _liquidity);
        }

        // @dev Set user's deposit info in deposits mapping.
        deposits[currentDepositId] = userDeposit;

        emit Deposited(currentDepositId, _account, _lockup, _liquidity);
        return currentDepositId;
    }

    /// @notice Common logic for initiating cooldown.
    /// @param _depositId User's deposit Id.
    function _initiateCooldown(uint256 _depositId) internal {
        _validateFarmActive();
        _validateDeposit(msg.sender, _depositId);
        Deposit storage userDeposit = deposits[_depositId];

        // Validate if the deposit is in locked state.
        if (userDeposit.cooldownPeriod == 0) {
            revert CannotInitiateCooldown();
        }

        // Update the deposit expiry time & lock status.
        userDeposit.expiryDate = block.timestamp + userDeposit.cooldownPeriod;
        userDeposit.cooldownPeriod = 0;

        // Claim the pending rewards for the user.
        _updateAndClaimFarmRewards(msg.sender, _depositId);

        // Unsubscribe the deposit from the lockup reward fund.
        _unsubscribeRewardFund(LOCKUP_FUND_ID, _depositId);

        emit CooldownInitiated(_depositId, userDeposit.expiryDate);
    }

    /// @notice Common logic for withdraw.
    /// @param _account address of the user.
    /// @param _depositId user's deposit id.
    function _withdraw(address _account, uint256 _depositId) internal {
        _validateDeposit(msg.sender, _depositId);
        // Check for the withdrawal criteria.
        // Note: If farm is paused, skip the cooldown check.
        if (isFarmActive()) {
            Deposit storage userDeposit = deposits[_depositId];
            if (userDeposit.cooldownPeriod != 0) {
                revert PleaseInitiateCooldown();
            }
            uint256 expiryDate = userDeposit.expiryDate;
            if (expiryDate != 0) {
                // Cooldown is initiated for the user.
                if (expiryDate > block.timestamp) {
                    revert DepositIsInCooldown();
                }
            }
        }

        // Compute the user's unclaimed rewards.
        _updateAndClaimFarmRewards(_account, _depositId);

        // unsubscribe the user from the common reward fund.
        _unsubscribeRewardFund(COMMON_FUND_ID, _depositId);

        if (subscriptions[_depositId].length != 0) {
            // To handle a lockup withdraw without cooldown (during farmPause).
            _unsubscribeRewardFund(LOCKUP_FUND_ID, _depositId);
        }

        // Delete user's deposit info from deposits mapping.
        delete deposits[_depositId];

        emit DepositWithdrawn(_depositId);
    }

    /// @notice Claim rewards for the user.
    /// @param _account The user's address.
    /// @param _depositId The id of the deposit.
    /// @dev NOTE: any function calling this private
    ///     function should be marked as non-reentrant.
    function _updateAndClaimFarmRewards(address _account, uint256 _depositId) internal {
        _updateFarmRewardData();

        Deposit storage userDeposit = deposits[_depositId];
        Subscription[] storage depositSubs = subscriptions[_depositId];

        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        uint256[] memory totalRewards = new uint256[](numRewards);
        uint256[][] memory rewardsForEachSubs = new uint256[][](numSubs);

        // Compute the rewards for each subscription.
        for (uint8 iSub; iSub < numSubs;) {
            uint8 fundId = depositSubs[iSub].fundId;
            uint256[] memory rewards = new uint256[](numRewards);
            rewardsForEachSubs[iSub] = new uint256[](numRewards);
            RewardFund storage fund = rewardFunds[fundId];

            for (uint256 iRwd; iRwd < numRewards;) {
                // rewards = (liquidity * accRewardPerShare) / PREC - rewardDebt
                uint256 accRewards = (userDeposit.liquidity * fund.accRewardPerShare[iRwd]) / PREC;
                rewards[iRwd] = accRewards - depositSubs[iSub].rewardDebt[iRwd];
                totalRewards[iRwd] += rewards[iRwd];

                depositSubs[iSub].rewardClaimed[iRwd] += rewards[iRwd];
                // Update userRewardDebt for the subscriptions
                // rewardDebt = liquidity * accRewardPerShare
                depositSubs[iSub].rewardDebt[iRwd] = accRewards;
                unchecked {
                    ++iRwd;
                }
            }
            rewardsForEachSubs[iSub] = rewards;

            unchecked {
                ++iSub;
            }
        }

        emit RewardsClaimed(_depositId, rewardsForEachSubs);

        // Transfer the claimed rewards to the user if any.
        for (uint8 iRwd; iRwd < numRewards;) {
            if (totalRewards[iRwd] != 0) {
                address rewardToken = rewardTokens[iRwd];
                rewardData[rewardToken].accRewardBal -= totalRewards[iRwd];
                // Update the total rewards earned for the deposit.
                userDeposit.totalRewardsClaimed[iRwd] += totalRewards[iRwd];
                IERC20(rewardToken).safeTransfer(_account, totalRewards[iRwd]);
            }
            unchecked {
                ++iRwd;
            }
        }
    }

    /// @notice Get the remaining balance out of the farm.
    /// @param _rwdToken The reward token's address.
    /// @param _amount The amount of the reward token to be withdrawn.
    /// @dev Function recovers minOf(_amount, rewardsLeft).
    /// @dev In case of partial withdraw of funds, the reward rate has to be set manually again.
    function _recoverRewardFunds(address _rwdToken, uint256 _amount) internal {
        address recoverTo = rewardData[_rwdToken].tknManager;
        uint256 rewardsLeft = getRewardBalance(_rwdToken);
        if (_amount >= rewardsLeft) {
            _amount = rewardsLeft;
        }
        if (_amount != 0) {
            IERC20(_rwdToken).safeTransfer(recoverTo, _amount);
            emit FundsRecovered(recoverTo, _rwdToken, _amount);
        }
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address.
    /// @param _newRewardRates The new reward rate for the fund (includes the precision).
    function _setRewardRate(address _rwdToken, uint256[] memory _newRewardRates) internal {
        uint8 id = rewardData[_rwdToken].id;
        uint256 numFunds = rewardFunds.length;
        if (_newRewardRates.length != numFunds) {
            revert InvalidRewardRatesLength();
        }
        // Update the reward rate.
        for (uint8 iFund; iFund < numFunds;) {
            rewardFunds[iFund].rewardsPerSec[id] = _newRewardRates[iFund];
            unchecked {
                ++iFund;
            }
        }
        emit RewardRateUpdated(_rwdToken, _newRewardRates);
    }

    /// @notice Function to update the FarmRewardData for all funds.
    function _updateFarmRewardData() internal virtual {
        uint256 time = _getRewardAccrualTimeElapsed();
        if (time > 0) {
            // If farm is paused don't accrue any rewards,
            // only update the lastFundUpdateTime.
            if (isFarmActive()) {
                uint256 numFunds = rewardFunds.length;
                uint256 numRewards = rewardTokens.length;
                // Update the reward funds.
                for (uint8 iFund; iFund < numFunds;) {
                    RewardFund storage fund = rewardFunds[iFund];
                    if (fund.totalLiquidity != 0) {
                        for (uint8 iRwd; iRwd < numRewards;) {
                            // Get the accrued rewards for the time.
                            uint256 accRewards = _getAccRewards(iRwd, iFund, time);
                            rewardData[rewardTokens[iRwd]].accRewardBal += accRewards;
                            fund.accRewardPerShare[iRwd] += (accRewards * PREC) / fund.totalLiquidity;

                            unchecked {
                                ++iRwd;
                            }
                        }
                    }
                    unchecked {
                        ++iFund;
                    }
                }
            }
            _updateLastRewardAccrualTime();
        }
    }

    /// @notice Function to setup the reward funds and initialize the farm global params during construction.
    /// @param _farmStartTime - Time of farm start.
    /// @param _cooldownPeriod - cooldown period in days for locked deposits. Egs: 7 means 7 days.
    /// @param _rwdTokenData - Reward data for each reward token.
    function _setupFarm(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        RewardTokenData[] memory _rwdTokenData
    ) internal {
        if (_farmStartTime < block.timestamp) {
            revert InvalidFarmStartTime();
        }
        farmId = _farmId;
        _transferOwnership(msg.sender);
        // Initialize farm global params.
        lastFundUpdateTime = _farmStartTime;

        // Check for lockup functionality.
        // @dev If _cooldownPeriod is 0, then the lockup functionality is disabled for the farm.
        uint8 numFunds = 1;
        if (_cooldownPeriod != 0) {
            _validateCooldownPeriod(_cooldownPeriod);
            cooldownPeriod = _cooldownPeriod * 1 days;
            numFunds = 2;
        }

        // Setup reward related information.
        uint256 numRewards = _rwdTokenData.length;
        if (numRewards > MAX_NUM_REWARDS) {
            revert InvalidRewardData();
        }

        // Initialize fund storage.
        for (uint8 i; i < numFunds;) {
            RewardFund memory _rewardFund = RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: new uint256[](numRewards),
                accRewardPerShare: new uint256[](numRewards)
            });
            rewardFunds.push(_rewardFund);
            unchecked {
                ++i;
            }
        }

        // Initialize reward Data
        for (uint8 iRwd; iRwd < numRewards;) {
            _addRewardData(_rwdTokenData[iRwd].token, _rwdTokenData[iRwd].tknManager);
            unchecked {
                ++iRwd;
            }
        }

        emit FarmStartTimeUpdated(_farmStartTime);
    }

    /// @notice Adds new reward token to the farm.
    /// @param _token Address of the reward token to be added.
    /// @param _tknManager Address of the reward token Manager.
    function _addRewardData(address _token, address _tknManager) internal {
        // Validate if addresses are correct.
        _validateNonZeroAddr(_token);
        _validateNonZeroAddr(_tknManager);

        if (rewardData[_token].tknManager != address(0)) {
            revert RewardTokenAlreadyAdded();
        }

        rewardData[_token] = RewardData({id: uint8(rewardTokens.length), tknManager: _tknManager, accRewardBal: 0});

        // Add reward token in the list.
        rewardTokens.push(_token);

        emit RewardTokenAdded(_token, _tknManager);
    }

    /// @notice Update the last reward accrual time.
    function _updateLastRewardAccrualTime() internal virtual {
        lastFundUpdateTime = block.timestamp;
    }

    /// @notice Computes the accrued reward for a given fund id and time interval.
    /// @param _rwdId Id of the reward token.
    /// @param _fundId Id of the reward fund.
    /// @param _time Time interval for the reward computation.
    function _getAccRewards(uint8 _rwdId, uint8 _fundId, uint256 _time) internal view returns (uint256) {
        uint256 rewardsPerSec = rewardFunds[_fundId].rewardsPerSec[_rwdId];
        if (rewardsPerSec == 0) {
            return 0;
        }
        address rwdToken = rewardTokens[_rwdId];
        uint256 rwdSupply = IERC20(rwdToken).balanceOf(address(this));
        uint256 rwdAccrued = rewardData[rwdToken].accRewardBal;

        uint256 rwdBal = 0;
        // Calculate the available reward funds in the farm.
        if (rwdSupply > rwdAccrued) {
            unchecked {
                rwdBal = rwdSupply - rwdAccrued;
            }
        }
        // Calculate the rewards accrued in time.
        uint256 accRewards = rewardsPerSec * _time;
        // Cap the reward with the available balance.
        if (accRewards > rwdBal) {
            accRewards = rwdBal;
        }
        return accRewards;
    }

    /// @notice Validate the deposit for account.
    /// @param _account Address of the caller to be checked against depositor.
    /// @param _depositId Id of the deposit.
    function _validateDeposit(address _account, uint256 _depositId) internal view {
        if (deposits[_depositId].depositor != _account || _account == address(0)) {
            revert DepositDoesNotExist();
        }
    }

    /// @notice Validate if farm is open. Revert otherwise.
    /// @dev This function can be overridden to add any new/additional logic.
    function _validateFarmOpen() internal view {
        if (!isFarmOpen()) {
            revert FarmIsClosed();
        }
    }

    /// @notice Validate if farm is active. Revert otherwise.
    ///         Farm is active if it is not paused and not closed.
    /// @dev This function can be overridden to add any new/additional logic.
    function _validateFarmActive() internal view {
        _validateFarmOpen(); // although this is a redundant check, it will through appropriate error message.
        if (!isFarmActive()) {
            revert FarmIsInactive();
        }
    }

    /// @notice Validate the caller is the token Manager. Revert otherwise.
    /// @param _rwdToken Address of reward token.
    function _validateTokenManager(address _rwdToken) internal view {
        if (msg.sender != rewardData[_rwdToken].tknManager) {
            revert NotTheTokenManager();
        }
    }

    /// @notice Get the time elapsed since the last reward accrual.
    /// @return time The time elapsed since the last reward accrual.
    function _getRewardAccrualTimeElapsed() internal view virtual returns (uint256) {
        unchecked {
            return block.timestamp - lastFundUpdateTime;
        }
    }

    /// @notice An internal function to validate cooldown period.
    /// @param _cooldownPeriod Period to be validated.
    function _validateCooldownPeriod(uint256 _cooldownPeriod) internal pure {
        if (_cooldownPeriod > MAX_COOLDOWN_PERIOD || _cooldownPeriod == 0) {
            revert InvalidCooldownPeriod();
        }
    }

    /// @notice Validate address.
    /// @param _addr Address to be validated.
    function _validateNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }

    /// @notice Add subscription to the reward fund for a deposit.
    /// @param _depositId The unique ID of the deposit.
    /// @param _fundId The reward fund id.
    /// @param _liquidity The liquidity of the deposit.
    function _subscribeRewardFund(uint8 _fundId, uint256 _depositId, uint256 _liquidity) private {
        // Subscribe to the reward fund.
        uint256 numRewards = rewardTokens.length;
        Subscription memory subscription = Subscription({
            fundId: _fundId,
            rewardDebt: new uint256[](numRewards),
            rewardClaimed: new uint256[](numRewards)
        });

        // Initialize user's reward debt.
        for (uint8 iRwd; iRwd < numRewards;) {
            subscription.rewardDebt[iRwd] = (_liquidity * rewardFunds[_fundId].accRewardPerShare[iRwd]) / PREC;
            unchecked {
                ++iRwd;
            }
        }

        subscriptions[_depositId].push(subscription);

        // Update the totalLiquidity for the fund.
        rewardFunds[_fundId].totalLiquidity += _liquidity;
        emit PoolSubscribed(_depositId, _fundId);
    }

    /// @notice Unsubscribe a reward fund from a deposit.
    /// @param _fundId The reward fund id.
    /// @param _depositId The deposit id corresponding to the user.
    /// @dev The rewards claimed from the reward fund is persisted in the event.
    function _unsubscribeRewardFund(uint8 _fundId, uint256 _depositId) private {
        uint256 depositLiquidity = deposits[_depositId].liquidity;
        uint256 numRewards = rewardTokens.length;

        // Unsubscribe from the reward fund.
        Subscription[] storage depositSubs = subscriptions[_depositId];
        uint256 numSubs = depositSubs.length;
        for (uint256 iSub; iSub < numSubs;) {
            if (depositSubs[iSub].fundId == _fundId) {
                // Persist the reward information.
                uint256[] memory rewardClaimed = new uint256[](numRewards);

                for (uint8 iRwd; iRwd < numRewards;) {
                    rewardClaimed[iRwd] = depositSubs[iSub].rewardClaimed[iRwd];
                    unchecked {
                        ++iRwd;
                    }
                }

                // Delete the subscription from the list.
                depositSubs[iSub] = depositSubs[numSubs - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund.
                rewardFunds[_fundId].totalLiquidity -= depositLiquidity;

                emit PoolUnsubscribed(_depositId, _fundId, rewardClaimed);

                break;
            }
            unchecked {
                ++iSub;
            }
        }
    }
}