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
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {FarmStorage, IFarm} from "./FarmStorage.sol";
import {RewardTokenData, RewardFund, Subscription, Deposit, RewardData} from "./interfaces/DataTypes.sol";

/// @title Base Farm contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract contains the core logic for the Demeter farms.
abstract contract Farm is FarmStorage, OwnableUpgradeable, ReentrancyGuardUpgradeable, MulticallUpgradeable {
    using SafeERC20 for IERC20;

    // Disallow initialization of an implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IFarm
    function withdraw(uint256 _depositId) external virtual;

    /// @inheritdoc IFarm
    function claimRewards(uint256 _depositId) external {
        claimRewards(msg.sender, _depositId);
    }

    /// @inheritdoc IFarm
    function initiateCooldown(uint256 _depositId) external nonReentrant {
        _initiateCooldown(_depositId);
    }

    /// @inheritdoc IFarm
    function addRewards(address _rwdToken, uint256 _amount) external nonReentrant {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        _validateFarmOpen();
        _validateRewardToken(_rwdToken);

        updateFarmRewardData();
        IERC20(_rwdToken).safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardAdded(_rwdToken, _amount);
    }

    // --------------------- Admin  Functions ---------------------

    /// @inheritdoc IFarm
    function updateCooldownPeriod(uint256 _newCooldownPeriod) external onlyOwner {
        _validateFarmOpen();
        if (cooldownPeriod == 0) {
            revert FarmDoesNotSupportLockup();
        }
        _validateCooldownPeriod(_newCooldownPeriod);
        cooldownPeriod = _newCooldownPeriod * 1 days;
        emit CooldownPeriodUpdated(_newCooldownPeriod);
    }

    /// @inheritdoc IFarm
    function farmPauseSwitch(bool _isPaused) external onlyOwner {
        _validateFarmOpen();
        if (isPaused == _isPaused) {
            revert FarmAlreadyInRequiredState();
        }
        updateFarmRewardData();
        isPaused = _isPaused;
        emit FarmPaused(isPaused);
    }

    /// @inheritdoc IFarm
    function closeFarm() external onlyOwner nonReentrant {
        _validateFarmOpen();
        updateFarmRewardData();
        isPaused = true;
        isClosed = true;
        uint256 numRewards = rewardTokens.length;
        for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
            _recoverRewardFunds(rewardTokens[iRwd], type(uint256).max);
            _setRewardRate(rewardTokens[iRwd], new uint128[](rewardFunds.length));
        }
        emit FarmClosed();
    }

    /// @inheritdoc IFarm
    function recoverERC20(address _token) external onlyOwner nonReentrant {
        _recoverERC20(_token);
    }

    // --------------------- Token Manager Functions ---------------------
    /// @inheritdoc IFarm
    function recoverRewardFunds(address _rwdToken, uint256 _amount) external nonReentrant {
        _validateTokenManager(_rwdToken);
        updateFarmRewardData();
        _recoverRewardFunds(_rwdToken, _amount);
    }

    /// @inheritdoc IFarm
    function setRewardRate(address _rwdToken, uint128[] memory _newRewardRates) external {
        _validateFarmOpen();
        _validateTokenManager(_rwdToken);
        updateFarmRewardData();
        _setRewardRate(_rwdToken, _newRewardRates);
    }

    /// @inheritdoc IFarm
    function updateRewardData(address _rwdToken, address _newTknManager) external {
        _validateFarmOpen();
        _validateTokenManager(_rwdToken);
        _validateNonZeroAddr(_newTknManager);
        rewardData[_rwdToken].tknManager = _newTknManager;
        emit RewardDataUpdated(_rwdToken, _newTknManager);
    }

    /// @inheritdoc IFarm
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
        uint256[] memory accumulatedRewards = new uint256[](numRewards);

        // Update the two reward funds.
        for (uint8 iSub; iSub < numDepositSubs; ++iSub) {
            Subscription storage sub = depositSubs[iSub];
            rewards[iSub] = new uint256[](numRewards);
            uint8 fundId = sub.fundId;
            for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
                if (funds[fundId].totalLiquidity != 0 && isFarmActive()) {
                    uint256 accRewards = _getAccRewards(iRwd, fundId, time, accumulatedRewards[iRwd]); // accumulatedRewards is sent to consider the already accrued rewards.
                    accumulatedRewards[iRwd] += accRewards;
                    // update the accRewardPerShare for delta time.
                    funds[fundId].accRewardPerShare[iRwd] += (accRewards * PRECISION) / funds[fundId].totalLiquidity;
                }
                rewards[iSub][iRwd] =
                    ((userLiquidity * funds[fundId].accRewardPerShare[iRwd]) / PRECISION) - sub.rewardDebt[iRwd];
            }
        }
        return rewards;
    }

    /// @inheritdoc IFarm
    function getRewardFunds() external view returns (RewardFund[] memory) {
        return rewardFunds;
    }

    /// @inheritdoc IFarm
    function getRewardData(address _rwdToken) external view returns (RewardData memory) {
        return rewardData[_rwdToken];
    }

    /// @inheritdoc IFarm
    function getDepositInfo(uint256 _depositId) external view returns (Deposit memory) {
        if (_depositId == 0 || _depositId > totalDeposits) {
            revert DepositDoesNotExist();
        }
        return deposits[_depositId];
    }

    /// @inheritdoc IFarm
    function getNumSubscriptions(uint256 _depositId) external view returns (uint256) {
        return subscriptions[_depositId].length;
    }

    /// @inheritdoc IFarm
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

    /// @inheritdoc IFarm
    function getRewardRates(address _rwdToken) external view returns (uint256[] memory) {
        _validateRewardToken(_rwdToken);
        uint256 numFunds = rewardFunds.length;
        uint256[] memory rates = new uint256[](numFunds);
        uint8 id = rewardData[_rwdToken].id;
        for (uint8 iFund; iFund < numFunds; ++iFund) {
            rates[iFund] = rewardFunds[iFund].rewardsPerSec[id];
        }
        return rates;
    }

    /// @inheritdoc IFarm
    function getRewardFundInfo(uint8 _fundId) external view returns (RewardFund memory) {
        if (_fundId >= rewardFunds.length) {
            revert RewardFundDoesNotExist();
        }
        return rewardFunds[_fundId];
    }

    /// @inheritdoc IFarm
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @inheritdoc IFarm
    function getTokenAmounts() external view virtual returns (address[] memory, uint256[] memory);

    /// @inheritdoc IFarm
    function updateFarmRewardData() public virtual {
        uint256 time = _getRewardAccrualTimeElapsed();
        if (time > 0) {
            // Accrue rewards if farm is active.
            if (isFarmActive()) {
                uint256 numFunds = rewardFunds.length;
                uint256 numRewards = rewardTokens.length;
                // Update the reward funds.
                for (uint8 iFund; iFund < numFunds; ++iFund) {
                    RewardFund storage fund = rewardFunds[iFund];
                    if (fund.totalLiquidity != 0) {
                        for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
                            // Get the accrued rewards for the time.
                            uint256 accRewards = _getAccRewards(iRwd, iFund, time, 0); // _alreadyAccRewardBal is 0.
                            rewardData[rewardTokens[iRwd]].accRewardBal += accRewards;
                            fund.accRewardPerShare[iRwd] += (accRewards * PRECISION) / fund.totalLiquidity;
                        }
                    }
                }
            }
        }
        _updateLastRewardAccrualTime(); // Update the last reward accrual time.
    }

    /// @inheritdoc IFarm
    function claimRewards(address _account, uint256 _depositId) public nonReentrant {
        _validateFarmOpen();
        _validateDeposit(_account, _depositId);
        _updateAndClaimFarmRewards(_depositId);
    }

    /// @inheritdoc IFarm
    function updateFarmStartTime(uint256 _newStartTime) public virtual onlyOwner {
        _validateFarmOpen();
        if (farmStartTime <= block.timestamp) {
            revert FarmAlreadyStarted();
        }
        if (_newStartTime < block.timestamp) {
            revert InvalidTime();
        }

        farmStartTime = _newStartTime;

        emit FarmStartTimeUpdated(_newStartTime);
    }

    /// @inheritdoc IFarm
    function isFarmOpen() public view virtual returns (bool) {
        return !isClosed;
    }

    /// @inheritdoc IFarm
    function isFarmActive() public view virtual returns (bool) {
        return !isPaused && isFarmOpen();
    }

    /// @inheritdoc IFarm
    function getRewardBalance(address _rwdToken) public view returns (uint256) {
        RewardData memory rwdData = rewardData[_rwdToken];

        _validateRewardToken(_rwdToken);

        uint256 numFunds = rewardFunds.length;
        uint256 rewardsAcc = rwdData.accRewardBal;
        uint256 supply = IERC20(_rwdToken).balanceOf(address(this));
        uint256 time = _getRewardAccrualTimeElapsed();
        if (time != 0) {
            for (uint8 iFund; iFund < numFunds; ++iFund) {
                if (rewardFunds[iFund].totalLiquidity != 0) {
                    rewardsAcc += rewardFunds[iFund].rewardsPerSec[rwdData.id] * time;
                }
            }
        }
        if (rewardsAcc >= supply) {
            return 0;
        }
        return (supply - rewardsAcc);
    }

    function _recoverERC20(address _token) internal virtual {
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
    /// @return The deposit id.
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
        updateFarmRewardData();

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            depositor: _account,
            liquidity: _liquidity,
            expiryDate: 0,
            cooldownPeriod: 0,
            depositTs: block.timestamp,
            totalRewardsClaimed: new uint256[](rewardTokens.length)
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
        _updateAndClaimFarmRewards(_depositId);

        // Unsubscribe the deposit from the lockup reward fund.
        _unsubscribeRewardFund(LOCKUP_FUND_ID, _depositId);

        emit CooldownInitiated(_depositId, userDeposit.expiryDate);
    }

    /// @notice Common logic for withdraw.
    /// @param _depositId User's deposit id.
    function _withdraw(uint256 _depositId) internal {
        _validateDeposit(msg.sender, _depositId);
        // Check for the withdrawal criteria.
        // Note: If farm is paused, skip the cooldown check.
        if (isFarmActive()) {
            Deposit storage userDeposit = deposits[_depositId];
            _validateNotRecentDeposit(userDeposit.depositTs);
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

        // Computes the user's unclaimed rewards and sends it.
        _updateAndClaimFarmRewards(_depositId);

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
    /// @param _depositId The id of the deposit.
    /// @dev NOTE: any function calling this private
    ///     function should be marked as non-reentrant.
    function _updateAndClaimFarmRewards(uint256 _depositId) internal {
        updateFarmRewardData();

        Deposit storage userDeposit = deposits[_depositId];
        Subscription[] storage depositSubs = subscriptions[_depositId];

        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        uint256[] memory totalRewards = new uint256[](numRewards);
        uint256[][] memory rewardsForEachSubs = new uint256[][](numSubs);

        // Compute the rewards for each subscription.
        for (uint8 iSub; iSub < numSubs; ++iSub) {
            uint8 fundId = depositSubs[iSub].fundId;
            uint256[] memory rewards = new uint256[](numRewards);
            rewardsForEachSubs[iSub] = new uint256[](numRewards);
            RewardFund storage fund = rewardFunds[fundId];

            for (uint256 iRwd; iRwd < numRewards; ++iRwd) {
                // rewards = (liquidity * accRewardPerShare) / PRECISION - rewardDebt
                uint256 accRewards = (userDeposit.liquidity * fund.accRewardPerShare[iRwd]) / PRECISION;
                rewards[iRwd] = accRewards - depositSubs[iSub].rewardDebt[iRwd];
                totalRewards[iRwd] += rewards[iRwd];

                depositSubs[iSub].rewardClaimed[iRwd] += rewards[iRwd];
                // Update userRewardDebt for the subscriptions
                // rewardDebt = liquidity * accRewardPerShare
                depositSubs[iSub].rewardDebt[iRwd] = accRewards;
            }
            rewardsForEachSubs[iSub] = rewards;
        }

        emit RewardsClaimed(_depositId, rewardsForEachSubs);

        address user = userDeposit.depositor;
        // Transfer the claimed rewards to the user if any.
        for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
            if (totalRewards[iRwd] != 0) {
                address rewardToken = rewardTokens[iRwd];
                rewardData[rewardToken].accRewardBal -= totalRewards[iRwd];
                // Update the total rewards earned for the deposit.
                userDeposit.totalRewardsClaimed[iRwd] += totalRewards[iRwd];
                IERC20(rewardToken).safeTransfer(user, totalRewards[iRwd]);
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
    function _setRewardRate(address _rwdToken, uint128[] memory _newRewardRates) internal {
        uint8 id = rewardData[_rwdToken].id;
        uint256 numFunds = rewardFunds.length;
        if (_newRewardRates.length != numFunds) {
            revert InvalidRewardRatesLength();
        }
        // Update the reward rate.
        for (uint8 iFund; iFund < numFunds; ++iFund) {
            rewardFunds[iFund].rewardsPerSec[id] = _newRewardRates[iFund];
        }
        emit RewardRateUpdated(_rwdToken, _newRewardRates);
    }

    /// @notice Function to setup the reward funds and initialize the farm global params during construction.
    /// @param _farmId ID of the farm. E.g: `Demeter_Camelot_V2`.
    /// @param _farmStartTime - Farm start time.
    /// @param _cooldownPeriod - Cooldown period in days for locked deposits. E.g: 7 means 7 days.
    /// @param _rwdTokenData - Reward data for each reward token.
    function _setupFarm(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        RewardTokenData[] memory _rwdTokenData
    ) internal initializer {
        if (_farmStartTime < block.timestamp) {
            revert InvalidFarmStartTime();
        }
        farmId = _farmId;
        __Ownable_init_unchained(msg.sender);
        // Initialize farm global params.
        farmStartTime = _farmStartTime;

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
        for (uint8 i; i < numFunds; ++i) {
            RewardFund memory _rewardFund = RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: new uint256[](numRewards),
                accRewardPerShare: new uint256[](numRewards)
            });
            rewardFunds.push(_rewardFund);
        }

        // Initialize reward Data.
        for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
            _addRewardData(_rwdTokenData[iRwd].token, _rwdTokenData[iRwd].tknManager);
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
    /// @param _alreadyAccRewardBal Already accrued reward balance.
    /// @dev `_alreadyAccRewardBal` is useful when this function called from `computeRewards` function.
    /// As `computeReward` is a view function and it doesn't update the `accRewardBal` in the `rewardData`.
    /// @return accRewards Accrued rewards for the given `_rwdId`, `_fundId` and `_time`.
    function _getAccRewards(uint8 _rwdId, uint8 _fundId, uint256 _time, uint256 _alreadyAccRewardBal)
        internal
        view
        returns (uint256)
    {
        uint256 rewardsPerSec = rewardFunds[_fundId].rewardsPerSec[_rwdId];
        if (rewardsPerSec == 0) {
            return 0;
        }
        address rwdToken = rewardTokens[_rwdId];
        uint256 rwdSupply = IERC20(rwdToken).balanceOf(address(this));
        uint256 rwdAccrued = rewardData[rwdToken].accRewardBal + _alreadyAccRewardBal;

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

    /// @notice A function to validate deposit ts to prevent flash loan vulnerabilities
    /// @param _depositTs depositTs of user's deposit. (It represents deposit ts or increaseDeposit ts)
    /// @dev Reverts when deposit made in the same transaction.
    function _validateNotRecentDeposit(uint256 _depositTs) internal view {
        if (_depositTs == block.timestamp) {
            revert WithdrawTooSoon();
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

    /// @notice Validate the reward token is valid.
    /// @param _rwdToken Address of reward token.
    function _validateRewardToken(address _rwdToken) internal view {
        if (rewardData[_rwdToken].tknManager == address(0)) {
            revert InvalidRewardToken();
        }
    }

    /// @notice Get the time elapsed since the last reward accrual.
    /// @return time The time elapsed since the last reward accrual.
    function _getRewardAccrualTimeElapsed() internal view virtual returns (uint256) {
        if (farmStartTime > block.timestamp || lastFundUpdateTime == 0) {
            return 0;
        }
        unchecked {
            return block.timestamp - lastFundUpdateTime; // lastFundUpdateTime is always equal or less than block.timestamp.
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
    /// @param _fundId The reward fund id.
    /// @param _depositId The unique ID of the deposit.
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
        for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
            subscription.rewardDebt[iRwd] = (_liquidity * rewardFunds[_fundId].accRewardPerShare[iRwd]) / PRECISION;
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
        for (uint256 iSub; iSub < numSubs; ++iSub) {
            if (depositSubs[iSub].fundId == _fundId) {
                // Persist the reward information.
                uint256[] memory rewardClaimed = new uint256[](numRewards);

                for (uint8 iRwd; iRwd < numRewards; ++iRwd) {
                    rewardClaimed[iRwd] = depositSubs[iSub].rewardClaimed[iRwd];
                }

                // Delete the subscription from the list.
                depositSubs[iSub] = depositSubs[numSubs - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund.
                rewardFunds[_fundId].totalLiquidity -= depositLiquidity;

                emit PoolUnsubscribed(_depositId, _fundId, rewardClaimed);

                break;
            }
        }
    }
}
