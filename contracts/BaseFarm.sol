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

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IFarmFactory} from "./interfaces/IFarmFactory.sol";

// Defines the reward data for constructor.
// token - Address of the token
// tknManager - Authority to update rewardToken related Params.
struct RewardTokenData {
    address token;
    address tknManager;
}

abstract contract BaseFarm is Ownable, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;

    // Defines the reward funds for the farm
    // totalLiquidity - amount of liquidity sharing the rewards in the fund
    // rewardsPerSec - the emission rate of the fund
    // accRewardPerShare - the accumulated reward per share
    struct RewardFund {
        uint256 totalLiquidity;
        uint256[] rewardsPerSec;
        uint256[] accRewardPerShare;
    }

    // Keeps track of a deposit's share in a reward fund.
    // fund id - id of the subscribed reward fund
    // rewardDebt - rewards claimed for a deposit corresponding to
    //              latest accRewardPerShare value of the budget
    // rewardClaimed - rewards claimed for a deposit from the reward fund
    struct Subscription {
        uint8 fundId;
        uint256[] rewardDebt;
        uint256[] rewardClaimed;
    }

    // Deposit information
    // liquidity - amount of liquidity in the deposit
    // tokenId - maps to uniswap NFT token id
    // startTime - time of deposit
    // expiryDate - expiry time (if deposit is locked)
    // cooldownPeriod - cooldown period (if deposit is locked)
    // totalRewardsClaimed - total rewards claimed for the deposit
    struct Deposit {
        uint256 liquidity;
        uint256 tokenId;
        uint256 startTime;
        uint256 expiryDate;
        uint256 cooldownPeriod;
        uint256[] totalRewardsClaimed;
    }

    // Reward token related information
    // tknManager - Address that manages the rewardToken.
    // id - Id of the rewardToken in the rewardTokens array.
    // accRewardBal - The rewards accrued but pending to be claimed.
    struct RewardData {
        address tknManager;
        uint8 id;
        uint256 accRewardBal;
    }

    // constants
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant SPA_TOKEN_MANAGER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188; // GaugeSPARewarder
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    uint256 public constant PREC = 1e18;
    uint256 public constant MIN_COOLDOWN_PERIOD = 1; // In days
    uint256 public constant MAX_COOLDOWN_PERIOD = 30; // In days
    uint256 public constant MAX_NUM_REWARDS = 4;

    // Global Params
    address public farmFactory;
    bool public isPaused;
    bool public isClosed;

    uint256 public cooldownPeriod;
    uint256 public lastFundUpdateTime;
    uint256 public farmEndTime;

    // Reward info
    RewardFund[] public rewardFunds;
    address[] public rewardTokens;
    mapping(address => RewardData) public rewardData;
    mapping(address => Deposit[]) public deposits;
    mapping(uint256 => Subscription[]) public subscriptions;

    event Deposited(address indexed account, bool locked, uint256 tokenId, uint256 liquidity);
    event CooldownInitiated(address indexed account, uint256 indexed tokenId, uint256 expiryDate);
    event DepositWithdrawn(
        address indexed account, uint256 tokenId, uint256 startTime, uint256 liquidity, uint256[] totalRewardsClaimed
    );
    event RewardsClaimed(address indexed account, uint256[][] rewardsForEachSubs);
    event PoolUnsubscribed(address indexed account, uint8 fundId, uint256 depositId, uint256[] totalRewardsClaimed);
    event FarmStartTimeUpdated(uint256 newStartTime);
    event FarmEndTimeUpdated(uint256 newEndTime);
    event CooldownPeriodUpdated(uint256 oldCooldownPeriod, uint256 newCooldownPeriod);
    event RewardRateUpdated(address indexed rwdToken, uint256[] newRewardRate);
    event RewardAdded(address rwdToken, uint256 amount);
    event FarmClosed();
    event RecoveredERC20(address token, uint256 amount);
    event FundsRecovered(address indexed account, address rwdToken, uint256 amount);
    event TokenManagerUpdated(address rwdToken, address oldTokenManager, address newTokenManager);
    event RewardTokenAdded(address rwdToken, address rwdTokenManager);
    event FarmPaused(bool paused);
    event ExtensionFeeCollected(address indexed creator, address token, uint256 extensionFee);

    // Custom Errors
    error InvalidRewardToken();
    error FarmDoesNotSupportLockup();
    error FarmAlreadyStarted();
    error InvalidTime();
    error InvalidExtension();
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
    error FarmNotYetStarted();
    error FarmHasExpired();
    error FarmIsPaused();
    error NotTheTokenManager();
    error InvalidAddress();
    error ZeroAmount();
    error InvalidCooldownPeriod();

    // Disallow initialization of a implementation contract
    constructor() {
        _disableInitializers();
    }

    function initiateCooldown(uint256 _depositId) external virtual;
    function withdraw(uint256 _depositId) external virtual;

    /// @notice Claim rewards for the user.
    /// @param _depositId The id of the deposit
    function claimRewards(uint256 _depositId) external {
        claimRewards(msg.sender, _depositId);
    }

    /// @notice Add rewards to the farm.
    /// @param _rwdToken the reward token's address.
    /// @param _amount the amount of reward tokens to add.
    function addRewards(address _rwdToken, uint256 _amount) external nonReentrant {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        _farmNotClosedOrExpired();
        if (rewardData[_rwdToken].tknManager == address(0)) {
            revert InvalidRewardToken();
        }
        _updateFarmRewardData();
        IERC20(_rwdToken).safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardAdded(_rwdToken, _amount);
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Update the cooldown period
    /// @param _newCooldownPeriod The new cooldown period (in days)
    function updateCooldownPeriod(uint256 _newCooldownPeriod) external onlyOwner {
        _farmNotClosedOrExpired();
        uint256 oldCooldownPeriod = cooldownPeriod;
        if (oldCooldownPeriod == 0) {
            revert FarmDoesNotSupportLockup();
        }
        _isValidCooldownPeriod(_newCooldownPeriod);
        cooldownPeriod = _newCooldownPeriod;
        emit CooldownPeriodUpdated(oldCooldownPeriod, _newCooldownPeriod);
    }

    /// @notice Update the farm start time.
    /// @dev Can be updated only before the farm start
    ///      New start time should be in future.
    /// @param _newStartTime The new farm start time.
    function updateFarmStartTime(uint256 _newStartTime) external onlyOwner {
        _farmNotClosedOrExpired();
        if (lastFundUpdateTime <= block.timestamp) {
            revert FarmAlreadyStarted();
        }
        if (_newStartTime < block.timestamp) {
            revert InvalidTime();
        }

        if (_newStartTime < lastFundUpdateTime) {
            uint256 timeDelta = lastFundUpdateTime - _newStartTime;
            farmEndTime = farmEndTime - timeDelta;
            emit FarmEndTimeUpdated(farmEndTime);
        }

        if (_newStartTime > lastFundUpdateTime) {
            uint256 timeDelta = _newStartTime - lastFundUpdateTime;
            farmEndTime = farmEndTime + timeDelta;
            emit FarmEndTimeUpdated(farmEndTime);
        }

        lastFundUpdateTime = _newStartTime;

        emit FarmStartTimeUpdated(_newStartTime);
    }

    /// @notice Update the farm end time.
    /// @dev Can be updated only before the farm expired or closed
    ///      extension should be incremented in multiples of 1 USDs/day with minimum of 100 days at a time and a maximum of 300 days
    ///      extension is possible only after farm started
    /// @param _extensionDays The number of days to extend the farm
    function extendFarmEndTime(uint256 _extensionDays) external onlyOwner {
        _farmNotClosedOrExpired();
        if (lastFundUpdateTime > block.timestamp) {
            revert FarmNotYetStarted();
        }
        if (_extensionDays < 100 || _extensionDays > 300) {
            revert InvalidExtension();
        }

        _collectFee(_extensionDays);

        farmEndTime = farmEndTime + _extensionDays * 1 days;

        emit FarmEndTimeUpdated(farmEndTime);
    }

    /// @notice Pause / UnPause the deposit
    function farmPauseSwitch(bool _isPaused) external onlyOwner {
        _farmNotClosedOrExpired();
        if (isPaused == _isPaused) {
            revert FarmAlreadyInRequiredState();
        }
        _updateFarmRewardData();
        isPaused = _isPaused;
        emit FarmPaused(isPaused);
    }

    /// @notice Recover rewardToken from the farm in case of EMERGENCY
    /// @dev Shuts down the farm completely
    function closeFarm() external onlyOwner nonReentrant {
        _farmNotClosedOrExpired();
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
    /// @param _token Address of token to be recovered
    function recoverERC20(address _token) external virtual onlyOwner nonReentrant {
        if (rewardData[_token].tknManager != address(0)) {
            revert CannotWithdrawRewardToken();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert CannotWithdrawZeroAmount();
        }

        IERC20(_token).safeTransfer(owner(), balance);
        emit RecoveredERC20(_token, balance);
    }

    // --------------------- Token Manager Functions ---------------------
    /// @notice Get the remaining balance out of the  farm
    /// @param _rwdToken The reward token's address
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    function recoverRewardFunds(address _rwdToken, uint256 _amount) external nonReentrant {
        _isTokenManager(_rwdToken);
        _updateFarmRewardData();
        _recoverRewardFunds(_rwdToken, _amount);
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address
    /// @param _newRewardRates The new reward rate for the fund (includes the precision)
    function setRewardRate(address _rwdToken, uint256[] memory _newRewardRates) external {
        _farmNotClosedOrExpired();
        _isTokenManager(_rwdToken);
        _updateFarmRewardData();
        _setRewardRate(_rwdToken, _newRewardRates);
    }

    /// @notice Transfer the tokenManagerRole to other user.
    /// @dev Only the existing tokenManager for a reward can call this function.
    /// @param _rwdToken The reward token's address.
    /// @param _newTknManager Address of the new token manager.
    function updateTokenManager(address _rwdToken, address _newTknManager) external {
        _farmNotClosedOrExpired();
        _isTokenManager(_rwdToken);
        _isNonZeroAddr(_newTknManager);
        rewardData[_rwdToken].tknManager = _newTknManager;
        emit TokenManagerUpdated(_rwdToken, msg.sender, _newTknManager);
    }

    /// @notice Function to compute the total accrued rewards for a deposit
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @return rewards The total accrued rewards for the deposit (uint256[])
    function computeRewards(address _account, uint256 _depositId) external view returns (uint256[] memory rewards) {
        _isValidDeposit(_account, _depositId);
        Deposit memory userDeposit = deposits[_account][_depositId];
        Subscription[] memory depositSubs = subscriptions[userDeposit.tokenId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numDepositSubs = depositSubs.length;
        uint256 numRewards = rewardTokens.length;
        rewards = new uint256[](numRewards);

        uint256 time = 0;
        // In case the reward is not updated
        if (block.timestamp > lastFundUpdateTime) {
            unchecked {
                time = block.timestamp - lastFundUpdateTime;
            }
        }

        // Update the two reward funds.
        for (uint8 iSub; iSub < numDepositSubs;) {
            Subscription memory sub = depositSubs[iSub];
            uint8 fundId = sub.fundId;
            for (uint8 iRwd; iRwd < numRewards;) {
                if (funds[fundId].totalLiquidity != 0 && !isPaused) {
                    uint256 accRewards = _getAccRewards(iRwd, fundId, time);
                    // update the accRewardPerShare for delta time.
                    funds[fundId].accRewardPerShare[iRwd] += (accRewards * PREC) / funds[fundId].totalLiquidity;
                }
                rewards[iRwd] +=
                    ((userDeposit.liquidity * funds[fundId].accRewardPerShare[iRwd]) / PREC) - sub.rewardDebt[iRwd];
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

    /// @notice get number of deposits for an account
    /// @param _account The user's address
    function getNumDeposits(address _account) external view returns (uint256) {
        return deposits[_account].length;
    }

    /// @notice get deposit info for an account
    /// @notice _account The user's address
    /// @notice _depositId The id of the deposit
    function getDeposit(address _account, uint256 _depositId) external view returns (Deposit memory) {
        return deposits[_account][_depositId];
    }

    /// @notice get number of deposits for an account
    /// @param _tokenId The token's id
    function getNumSubscriptions(uint256 _tokenId) external view returns (uint256) {
        return subscriptions[_tokenId].length;
    }

    /// @notice get subscription stats for a deposit.
    /// @param _tokenId The token's id
    /// @param _subscriptionId The subscription's id
    function getSubscriptionInfo(uint256 _tokenId, uint256 _subscriptionId)
        external
        view
        returns (Subscription memory)
    {
        if (_subscriptionId >= subscriptions[_tokenId].length) {
            revert SubscriptionDoesNotExist();
        }
        return subscriptions[_tokenId][_subscriptionId];
    }

    /// @notice get reward rates for a rewardToken.
    /// @param _rwdToken The reward token's address
    /// @return The reward rates for the reward token (uint256[])
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

    /// @notice get farm reward fund info.
    /// @param _fundId The fund's id
    function getRewardFundInfo(uint8 _fundId) external view returns (RewardFund memory) {
        if (_fundId >= rewardFunds.length) {
            revert RewardFundDoesNotExist();
        }
        return rewardFunds[_fundId];
    }

    /// @notice Claim rewards for the user.
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @dev Anyone can call this function to claim rewards for the user
    function claimRewards(address _account, uint256 _depositId) public nonReentrant {
        _farmNotClosedOrExpired();
        _isValidDeposit(_account, _depositId);
        _claimRewards(_account, _depositId);
    }

    /// @notice Get the remaining reward balance for the farm.
    /// @param _rwdToken The reward token's address
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

    /// @notice Common logic for deposit in the demeter farm.
    /// @param _account Address of the user
    /// @param _lockup lockup option for the deposit.
    /// @param _tokenId generated | provided id of position to be deposited.
    /// @param _liquidity Liquidity amount to be added to the pool.
    function _deposit(address _account, bool _lockup, uint256 _tokenId, uint256 _liquidity) internal {
        // Allow deposit only when farm is not paused.
        _farmNotPaused();

        if (cooldownPeriod == 0) {
            if (_lockup) {
                revert LockupFunctionalityIsDisabled();
            }
        }

        if (_liquidity == 0) {
            revert NoLiquidityInPosition();
        }
        // update the reward funds
        _updateFarmRewardData();

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            cooldownPeriod: 0,
            tokenId: _tokenId,
            startTime: block.timestamp,
            expiryDate: 0,
            totalRewardsClaimed: new uint256[](rewardTokens.length),
            liquidity: _liquidity
        });
        // Add common fund subscription to the user's deposit
        _subscribeRewardFund(COMMON_FUND_ID, _tokenId, _liquidity);

        if (_lockup) {
            // Add lockup fund subscription to the user's deposit
            userDeposit.cooldownPeriod = cooldownPeriod;
            _subscribeRewardFund(LOCKUP_FUND_ID, _tokenId, _liquidity);
        }

        // @dev Add the deposit to the user's deposit list
        deposits[_account].push(userDeposit);

        emit Deposited(_account, _lockup, _tokenId, _liquidity);
    }

    /// @notice Common logic for initiating cooldown.
    /// @param _depositId user's deposit Id.
    function _initiateCooldown(uint256 _depositId) internal {
        _farmNotPaused();
        _isValidDeposit(msg.sender, _depositId);
        Deposit storage userDeposit = deposits[msg.sender][_depositId];

        // validate if the deposit is in locked state
        if (userDeposit.cooldownPeriod == 0) {
            revert CannotInitiateCooldown();
        }

        // update the deposit expiry time & lock status
        userDeposit.expiryDate = block.timestamp + (userDeposit.cooldownPeriod * 1 days);
        userDeposit.cooldownPeriod = 0;

        // claim the pending rewards for the user
        _claimRewards(msg.sender, _depositId);

        // Unsubscribe the deposit from the lockup reward fund
        _unsubscribeRewardFund(LOCKUP_FUND_ID, msg.sender, _depositId);

        emit CooldownInitiated(msg.sender, userDeposit.tokenId, userDeposit.expiryDate);
    }

    /// @notice Common logic for withdraw.
    /// @param _account address of the user.
    /// @param _depositId user's deposit id.
    /// @param _userDeposit userDeposit struct.
    function _withdraw(address _account, uint256 _depositId, Deposit memory _userDeposit) internal {
        // Check for the withdrawal criteria
        // Note: If farm is paused, skip the cooldown check
        if (!isPaused) {
            if (_userDeposit.cooldownPeriod != 0) {
                revert PleaseInitiateCooldown();
            }
            if (_userDeposit.expiryDate != 0) {
                // Cooldown is initiated for the user
                if (_userDeposit.expiryDate > block.timestamp) {
                    revert DepositIsInCooldown();
                }
            }
        }

        // Compute the user's unclaimed rewards
        _claimRewards(_account, _depositId);

        // Store the total rewards earned
        uint256[] memory totalRewards = deposits[_account][_depositId].totalRewardsClaimed;

        // unsubscribe the user from the common reward fund
        _unsubscribeRewardFund(COMMON_FUND_ID, _account, _depositId);

        if (subscriptions[_userDeposit.tokenId].length != 0) {
            // To handle a lockup withdraw without cooldown (during farmPause)
            _unsubscribeRewardFund(LOCKUP_FUND_ID, _account, _depositId);
        }

        // Update the user's deposit list
        deposits[_account][_depositId] = deposits[_account][deposits[_account].length - 1];
        deposits[_account].pop();

        emit DepositWithdrawn({
            account: _account,
            tokenId: _userDeposit.tokenId,
            startTime: _userDeposit.startTime,
            liquidity: _userDeposit.liquidity,
            totalRewardsClaimed: totalRewards
        });
    }

    /// @notice Claim rewards for the user.
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @dev NOTE: any function calling this private
    ///     function should be marked as non-reentrant
    function _claimRewards(address _account, uint256 _depositId) internal {
        _updateFarmRewardData();

        Deposit storage userDeposit = deposits[_account][_depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];

        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        uint256[] memory totalRewards = new uint256[](numRewards);
        uint256[][] memory rewardsForEachSubs = new uint256[][](numSubs);

        // Compute the rewards for each subscription.
        for (uint8 iSub; iSub < numSubs;) {
            uint8 fundId = depositSubs[iSub].fundId;
            uint256[] memory rewards = new uint256[](numRewards);
            rewardsForEachSubs[iSub] = new uint256[](numRewards);
            RewardFund memory fund = rewardFunds[fundId];

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

        emit RewardsClaimed(_account, rewardsForEachSubs);

        // Transfer the claimed rewards to the User if any.
        for (uint8 iRwd; iRwd < numRewards;) {
            if (totalRewards[iRwd] != 0) {
                rewardData[rewardTokens[iRwd]].accRewardBal -= totalRewards[iRwd];
                // Update the total rewards earned for the deposit
                userDeposit.totalRewardsClaimed[iRwd] += totalRewards[iRwd];
                IERC20(rewardTokens[iRwd]).safeTransfer(_account, totalRewards[iRwd]);
            }
            unchecked {
                ++iRwd;
            }
        }
    }

    /// @notice Get the remaining balance out of the  farm
    /// @param _rwdToken The reward token's address
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    /// @dev In case of partial withdraw of funds, the reward rate has to be set manually again.
    function _recoverRewardFunds(address _rwdToken, uint256 _amount) internal {
        address emergencyRet = rewardData[_rwdToken].tknManager;
        uint256 rewardsLeft = getRewardBalance(_rwdToken);
        uint256 amountToRecover = _amount;
        if (_amount >= rewardsLeft) {
            amountToRecover = rewardsLeft;
        }
        if (amountToRecover != 0) {
            IERC20(_rwdToken).safeTransfer(emergencyRet, amountToRecover);
            emit FundsRecovered(emergencyRet, _rwdToken, amountToRecover);
        }
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address
    /// @param _newRewardRates The new reward rate for the fund (includes the precision)
    function _setRewardRate(address _rwdToken, uint256[] memory _newRewardRates) internal {
        uint8 id = rewardData[_rwdToken].id;
        uint256 numFunds = rewardFunds.length;
        if (_newRewardRates.length != numFunds) {
            revert InvalidRewardRatesLength();
        }
        // Update the reward rate
        for (uint8 iFund; iFund < numFunds;) {
            rewardFunds[iFund].rewardsPerSec[id] = _newRewardRates[iFund];
            unchecked {
                ++iFund;
            }
        }
        emit RewardRateUpdated(_rwdToken, _newRewardRates);
    }

    /// @notice Function to update the FarmRewardData for all funds
    function _updateFarmRewardData() internal {
        if (block.timestamp > lastFundUpdateTime) {
            // if farm is paused don't accrue any rewards.
            // only update the lastFundUpdateTime.
            if (!isPaused) {
                uint256 time;
                unchecked {
                    time = block.timestamp - lastFundUpdateTime;
                }
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
            lastFundUpdateTime = block.timestamp;
        }
    }

    /// @notice Function to setup the reward funds during construction.
    /// @param _farmStartTime - Time of farm start.
    /// @param _cooldownPeriod - cooldown period for locked deposits.
    /// @param _rwdTokenData - Reward data for each reward token.
    function _setupFarm(uint256 _farmStartTime, uint256 _cooldownPeriod, RewardTokenData[] memory _rwdTokenData)
        internal
    {
        if (_farmStartTime < block.timestamp) {
            revert InvalidFarmStartTime();
        }
        _transferOwnership(msg.sender);
        // Initialize farm global params
        lastFundUpdateTime = _farmStartTime;
        farmEndTime = _farmStartTime + 100 days;

        // Check for lockup functionality
        // @dev If _cooldownPeriod is 0, then the lockup functionality is disabled for
        // the farm.
        uint8 numFunds = 1;
        if (_cooldownPeriod != 0) {
            _isValidCooldownPeriod(_cooldownPeriod);
            cooldownPeriod = _cooldownPeriod;
            numFunds = 2;
        }

        // Setup reward related information.
        uint256 numRewards = _rwdTokenData.length;
        if (numRewards > MAX_NUM_REWARDS - 1) {
            revert InvalidRewardData();
        }

        // Initialize fund storage
        for (uint8 i; i < numFunds;) {
            RewardFund memory _rewardFund = RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: new uint256[](numRewards + 1),
                accRewardPerShare: new uint256[](numRewards + 1)
            });
            rewardFunds.push(_rewardFund);
            unchecked {
                ++i;
            }
        }

        // Add SPA as default reward token in the farm
        _addRewardData(SPA, SPA_TOKEN_MANAGER);

        // Initialize reward Data
        for (uint8 iRwd; iRwd < numRewards;) {
            _addRewardData(_rwdTokenData[iRwd].token, _rwdTokenData[iRwd].tknManager);
            unchecked {
                ++iRwd;
            }
        }

        emit FarmStartTimeUpdated(_farmStartTime);
        emit FarmEndTimeUpdated(_farmStartTime + 100 days);
    }

    /// @notice Adds new reward token to the farm
    /// @param _token Address of the reward token to be added.
    /// @param _tknManager Address of the reward token Manager.
    function _addRewardData(address _token, address _tknManager) internal {
        // Validate if addresses are correct
        _isNonZeroAddr(_token);
        _isNonZeroAddr(_tknManager);

        if (rewardData[_token].tknManager != address(0)) {
            revert RewardTokenAlreadyAdded();
        }

        rewardData[_token] = RewardData({id: uint8(rewardTokens.length), tknManager: _tknManager, accRewardBal: 0});

        // Add reward token in the list
        rewardTokens.push(_token);

        emit RewardTokenAdded(_token, _tknManager);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
    function _collectFee(uint256 _extensionDays) internal {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list
        (address feeReceiver, address feeToken,, uint256 extensionFeePerDay) =
            IFarmFactory(farmFactory).getFeeParams(msg.sender);
        uint256 extensionFeeAmount;
        if (extensionFeePerDay != 0) {
            extensionFeeAmount = _extensionDays * extensionFeePerDay;
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, extensionFeeAmount);
            emit ExtensionFeeCollected(msg.sender, feeToken, extensionFeeAmount);
        }
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

    /// @notice Validate the deposit for account
    function _isValidDeposit(address _account, uint256 _depositId) internal view {
        if (_depositId >= deposits[_account].length) {
            revert DepositDoesNotExist();
        }
    }

    /// @notice Validate if farm is not closed or expired
    function _farmNotClosedOrExpired() internal view {
        if (isClosed) {
            revert FarmIsClosed();
        }
        if (block.timestamp > farmEndTime) {
            revert FarmHasExpired();
        }
    }

    /// @notice Validate if farm is not paused
    function _farmNotPaused() internal view {
        if (isPaused) {
            revert FarmIsPaused();
        }
    }

    /// @notice Validate the caller is the token Manager.
    function _isTokenManager(address _rwdToken) internal view {
        if (msg.sender != rewardData[_rwdToken].tknManager) {
            revert NotTheTokenManager();
        }
    }

    function _isValidCooldownPeriod(uint256 _cooldownPeriod) internal pure {
        if (_cooldownPeriod < MIN_COOLDOWN_PERIOD || _cooldownPeriod > MAX_COOLDOWN_PERIOD) {
            revert InvalidCooldownPeriod();
        }
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }

    /// @notice Add subscription to the reward fund for a deposit
    /// @param _tokenId The tokenId of the deposit
    /// @param _fundId The reward fund id
    /// @param _liquidity The liquidity of the deposit
    function _subscribeRewardFund(uint8 _fundId, uint256 _tokenId, uint256 _liquidity) private {
        // Subscribe to the reward fund
        uint256 numRewards = rewardTokens.length;
        subscriptions[_tokenId].push(
            Subscription({
                fundId: _fundId,
                rewardDebt: new uint256[](numRewards),
                rewardClaimed: new uint256[](numRewards)
            })
        );
        uint256 subId = subscriptions[_tokenId].length - 1;

        // initialize user's reward debt
        for (uint8 iRwd; iRwd < numRewards;) {
            subscriptions[_tokenId][subId].rewardDebt[iRwd] =
                (_liquidity * rewardFunds[_fundId].accRewardPerShare[iRwd]) / PREC;
            unchecked {
                ++iRwd;
            }
        }
        // Update the totalLiquidity for the fund
        rewardFunds[_fundId].totalLiquidity += _liquidity;
    }

    /// @notice Unsubscribe a reward fund from a deposit
    /// @param _fundId The reward fund id
    /// @param _account The user's address
    /// @param _depositId The deposit id corresponding to the user
    /// @dev The rewards claimed from the reward fund is persisted in the event
    function _unsubscribeRewardFund(uint8 _fundId, address _account, uint256 _depositId) private {
        Deposit memory userDeposit = deposits[_account][_depositId];
        uint256 numRewards = rewardTokens.length;

        // Unsubscribe from the reward fund
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        uint256 numSubs = depositSubs.length;
        for (uint256 iSub; iSub < numSubs;) {
            if (depositSubs[iSub].fundId == _fundId) {
                // Persist the reward information
                uint256[] memory rewardClaimed = new uint256[](numRewards);

                for (uint8 iRwd; iRwd < numRewards;) {
                    rewardClaimed[iRwd] = depositSubs[iSub].rewardClaimed[iRwd];
                    unchecked {
                        ++iRwd;
                    }
                }

                // Delete the subscription from the list
                depositSubs[iSub] = depositSubs[numSubs - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund
                rewardFunds[_fundId].totalLiquidity -= userDeposit.liquidity;

                emit PoolUnsubscribed(_account, _fundId, _depositId, rewardClaimed);

                break;
            }
            unchecked {
                ++iSub;
            }
        }
    }
}
