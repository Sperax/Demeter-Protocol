pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {INonfungiblePositionManager as INFPM, IUniswapV3Factory} from "../interfaces/UniswapV3.sol";

// Defines the Uniswap pool init data for constructor.
// tokenA - Address of tokenA
// tokenB - Address of tokenB
// feeTier - Fee tier for the Uniswap pool
// tickLowerAllowed - Lower bound of the tick range for farm
// tickUpperAllowed - Upper bound of the tick range for farm
struct UniswapPoolData {
    address tokenA;
    address tokenB;
    uint24 feeTier;
    int24 tickLowerAllowed;
    int24 tickUpperAllowed;
}

// Defines the reward data for constructor.
// token - Address of the token
// tknManager - Authority to update rewardToken related Params.
// emergencyReturn - Address to recover the token to in case of emergency.
// rewardRates - Reward rates for fund types. (max length is 2)
//               Only the first two elements would be considered
struct RewardTokenData {
    address token;
    address tknManager;
    address emergencyReturn;
    uint256[] rewardsPerSec;
}

contract Farm is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Defines the reward funds for the farm
    // totalLiquidity - amount of liquidity sharing the rewards in the fund
    // rewardsPerSec - the emision rate of the fund
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
    // rewardCalimed - rewards claimed for a deposit from the reward fund
    struct Subscription {
        uint8 fundId;
        uint256[] rewardDebt;
        uint256[] rewardClaimed;
    }

    // Deposit information
    // locked - determines if the deposit is locked or not
    // liquidity - amount of liquidity in the deposit
    // tokenId - maps to uniswap NFT token id
    // startTime - time of deposit
    // expiryDate - expiry time (if deposit is locked)
    // totalRewardsClaimed - total rewards claimed for the deposit
    struct Deposit {
        bool locked;
        uint256 liquidity;
        uint256 tokenId;
        uint256 startTime;
        uint256 expiryDate;
        uint256[] totalRewardsClaimed;
    }

    struct RewardData {
        uint8 id;
        address tknManager;
        address emergencyReturn;
        uint256 accRewards;
        uint256 supply;
    }

    // constants
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    address public constant NFPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant UNIV3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint256 public constant PREC = 1e18;
    uint256 public constant MIN_COOLDOWN_PERIOD = 2 days;

    // UniswapV3 params
    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    address public immutable uniswapPool;

    // Global Params
    bool public isPaused;
    bool public inEmergency;
    uint256 public farmStartTime;
    uint256 public cooldownPeriod;
    uint256 public lastFundUpdateTime;

    // Reward info
    RewardFund[] public rewardFunds;
    address[] public rewardTokens;
    mapping(address => RewardData) public rewardData;
    mapping(address => Deposit[]) public deposits;
    mapping(uint256 => Subscription[]) public subscriptions;

    event Deposited(
        address indexed account,
        bool locked,
        uint256 tokenId,
        uint256 liquidity
    );
    event CooldownInitiated(
        address indexed account,
        uint256 tokenId,
        uint256 expiryDate
    );
    event DepositWithdrawn(
        address indexed account,
        uint256 tokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 liquidity,
        uint256[] totalRewardsClaimed
    );
    event RewardsClaimed(
        address indexed account,
        uint8 fundId,
        uint256 tokenId,
        uint256 liquidity,
        uint256 fundLiquidity,
        uint256[] rewardAmount
    );
    event PoolUnsubscribed(
        address indexed account,
        uint256 depositId,
        uint8 fundId,
        uint256 startTime,
        uint256 endTime,
        uint256[] totalRewardsClaimed
    );
    event CooldownPeriodUpdated(
        uint256 oldCooldownPeriod,
        uint256 newCooldownPeriod
    );
    event RewardRateUpdated(
        uint8 fundId,
        address rewardToken,
        uint256 oldRewardRate,
        uint256 newRewardRate
    );
    event EmergencyClaim(address indexed account);
    event FundsRecovered(
        address indexed account,
        address rwdToken,
        uint256 amount
    );
    event DepositPaused(bool paused);

    modifier notPaused() {
        require(!isPaused, "Farm is paused");
        _;
    }

    modifier notInEmergency() {
        require(!inEmergency, "Emergency, Please withdraw");
        _;
    }

    // constructor
    constructor(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rewardData
    ) {
        // Initialize farm global params
        farmStartTime = _farmStartTime;

        // initialize uniswap related data
        tickLowerAllowed = _uniswapPoolData.tickLowerAllowed;
        tickUpperAllowed = _uniswapPoolData.tickUpperAllowed;
        uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            _uniswapPoolData.tokenB,
            _uniswapPoolData.tokenA,
            _uniswapPoolData.feeTier
        );

        // Check for lockup functionality
        // @dev If _cooldownPeriod is 0, then the lockup functionality is disabled for
        // the farm.
        uint8 numFunds = 1;
        if (_cooldownPeriod > 0) {
            require(
                _cooldownPeriod > MIN_COOLDOWN_PERIOD,
                "Cooldown period must be greater than or equal to "
            );
            cooldownPeriod = _cooldownPeriod;
            numFunds = 2;
        }
        _setupRewardFunds(numFunds, _rewardData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param from The address of the owner.
    /// @param tokenId nft Id generated by uniswap v3.
    /// @param data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override notPaused returns (bytes4) {
        require(
            _msgSender() == NFPM,
            "UniswapV3Staker::onERC721Received: not a univ3 nft"
        );

        require(data.length > 0, "UniswapV3Staker::onERC721Received: no data");

        bool lockup = abi.decode(data, (bool));

        // update the reward funds
        _updateFarmRewardData();

        // Validate the position and get the liquidity
        uint256 liquidity = _getLiquidity(tokenId);

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            locked: lockup,
            tokenId: tokenId,
            startTime: block.timestamp,
            expiryDate: 0,
            totalRewardsClaimed: new uint256[](rewardTokens.length),
            liquidity: liquidity
        });

        // @dev Add the deposit to the user's deposit list
        deposits[from].push(userDeposit);
        // Add common fund subscription to the user's deposit
        _subscribeRewardFund(COMMON_FUND_ID, userDeposit.tokenId, liquidity);

        if (lockup) {
            // Add lockup fund subscription to the user's deposit
            _subscribeRewardFund(
                LOCKUP_FUND_ID,
                userDeposit.tokenId,
                liquidity
            );
        }

        emit Deposited(from, lockup, tokenId, liquidity);
        return this.onERC721Received.selector;
    }

    /// @notice Function to lock a staked deposit
    /// @param depositId The id of the deposit to be locked
    /// @dev depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit storage userDeposit = deposits[account][depositId];

        // validate if the deposit is in locked state
        require(userDeposit.locked, "Can not initiate cooldown");

        // update the deposit expiry time & lock status
        userDeposit.expiryDate = block.timestamp + cooldownPeriod;
        userDeposit.locked = false;

        // claim the pending rewards for the user
        _claimRewards(account, depositId);

        // Unsubscribe the deposit from the lockup reward fund
        _unsubscribeRewardFund(LOCKUP_FUND_ID, account, depositId);

        emit CooldownInitiated(
            account,
            userDeposit.tokenId,
            userDeposit.expiryDate
        );
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param depositId The id of the deposit to be withdrawn
    function withdraw(uint256 depositId) external nonReentrant {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit memory userDeposit = deposits[account][depositId];

        // Check for the withdrawal criteria
        // Note: In case of emergency, skip the cooldown check
        if (!inEmergency) {
            require(!userDeposit.locked, "Please initiate cooldown");
            if (userDeposit.expiryDate > 0) {
                // Cooldown is initiated for the user
                require(
                    userDeposit.expiryDate <= block.timestamp,
                    "Deposit is in cooldown"
                );
            }
        }

        // Compute the user's unclaimed rewards
        _claimRewards(account, depositId);

        // Store the total rewards earned
        uint256[] memory totalRewards = deposits[account][depositId]
            .totalRewardsClaimed;

        // unsubscribe the user from the common reward fund
        _unsubscribeRewardFund(COMMON_FUND_ID, account, depositId);

        // Update the user's deposit list
        deposits[account][depositId] = deposits[account][
            deposits[account].length - 1
        ];
        deposits[account].pop();

        // Transfer the nft back to the user.
        INFPM(NFPM).safeTransferFrom(
            address(this),
            account,
            userDeposit.tokenId
        );

        emit DepositWithdrawn(
            account,
            userDeposit.tokenId,
            userDeposit.startTime,
            block.timestamp,
            userDeposit.liquidity,
            totalRewards
        );
    }

    /// @notice Claim rewards for the user.
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @dev Anyone can call this function to claim rewards for the user
    function claimRewards(address account, uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        require(deposits[account].length > depositId, "Deposit does not exist");
        _claimRewards(account, depositId);
    }

    /// @notice Claim rewards for the user.
    /// @param depositId The id of the deposit
    function claimRewards(uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        _claimRewards(account, depositId);
    }

    /// @notice Recover rewardToken from the farm in case of EMERGENCY
    /// @dev Shuts down the farm completely
    function declareEmergency() external onlyOwner {
        uint256 numRewards = rewardTokens.length;
        updateCooldownPeriod(0);
        toggleDepositPause();
        inEmergency = true;
        for (uint8 i = 0; i < numRewards; ++i) {
            address rwdToken = rewardTokens[i];
            address emergencyRet = rewardData[rwdToken].emergencyReturn;
            setRewardsPerSec(COMMON_FUND_ID, rwdToken, 0);
            setRewardsPerSec(LOCKUP_FUND_ID, rwdToken, 0);
            uint256 amount = IERC20(rwdToken).balanceOf(address(this));
            IERC20(rwdToken).safeTransfer(emergencyRet, amount);
            emit FundsRecovered(emergencyRet, rwdToken, amount);
        }
    }

    /// @notice Get the remaining balance out of the  farm
    /// @dev All the leftover funds are returned to the emergency address
    /// @param rwdToken The reward token's address
    function recoverRewardFunds(address rwdToken) external nonReentrant {
        require(
            _msgSender() == rewardData[rwdToken].tknManager,
            "Unauthorized call"
        );
        address emergencyRet = rewardData[rwdToken].emergencyReturn;
        // Update the total accumulated rewards here1
        _updateFarmRewardData();
        uint256 rewardsLeft = getRewardBalance(rwdToken);
        if (rewardsLeft > 0) {
            // Transfer the rewards to the common reward fund
            IERC20(rwdToken).safeTransfer(emergencyRet, rewardsLeft);
            emit FundsRecovered(emergencyRet, rwdToken, rewardsLeft);
        }
        /// @todo Should we add a revert otherwise??
    }

    /// @notice Add rewards to the farm.
    /// @dev Only the rwdToken manager can add the rewards.
    function addRewards(address rwdToken, uint256 amount)
        external
        nonReentrant
    {
        require(
            _msgSender() == rewardData[rwdToken].tknManager,
            "Unauthorized call"
        );
        rewardData[rwdToken].supply += amount;
        IERC20(rwdToken).safeTransferFrom(_msgSender(), address(this), amount);
    }

    /// @notice Function to compute the total accrued rewards for a deposit
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @return rewards The total accrued rewards for the deposit (uint256[])
    function computeRewards(address account, uint256 depositId)
        external
        view
        returns (uint256[] memory rewards)
    {
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit storage userDeposit = deposits[account][depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numRewards = rewardTokens.length;
        rewards = new uint256[](numRewards);

        // In case the reward is not updated
        if (block.timestamp > farmStartTime) {
            uint256 time = block.timestamp - lastFundUpdateTime;
            // Update the two reward funds.
            for (uint8 i = 0; i < depositSubs.length; ++i) {
                uint8 fundId = depositSubs[i].fundId;
                for (uint8 j = 0; j < numRewards; ++j) {
                    funds[fundId].accRewardPerShare[j] +=
                        (funds[fundId].rewardsPerSec[j] * time * PREC) /
                        funds[fundId].totalLiquidity;

                    rewards[j] +=
                        ((userDeposit.liquidity *
                            funds[fundId].accRewardPerShare[j]) / PREC) -
                        depositSubs[i].rewardDebt[j];
                }
            }
        }
        return rewards;
    }

    /// @notice get number of deposits for an account
    /// @param account The user's address
    function getNumDeposits(address account) external view returns (uint256) {
        return deposits[account].length;
    }

    /// @notice get deposit info for an account
    /// @notice account The user's address
    /// @notice depositId The id of the deposit
    function getDeposit(address account, uint256 depositId)
        external
        view
        returns (Deposit memory)
    {
        return deposits[account][depositId];
    }

    /// @notice get number of deposits for an account
    /// @param tokenId The token's id
    function getNumSubscriptions(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return subscriptions[tokenId].length;
    }

    /// @notice get subscription stats for a deposit.
    /// @param tokenId The token's id
    /// @param subscriptionId The subscription's id
    function getSubscriptionInfo(uint256 tokenId, uint256 subscriptionId)
        external
        view
        returns (Subscription memory)
    {
        require(
            subscriptions[tokenId].length > subscriptionId,
            "Subscription does not exist"
        );
        return subscriptions[tokenId][subscriptionId];
    }

    /// @notice get farm reward fund info.
    /// @param fundId The fund's id
    function getRewardFundInfo(uint8 fundId)
        external
        view
        returns (RewardFund memory)
    {
        return rewardFunds[fundId];
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Update the cooldown period
    /// @param newCooldownPeriod The new cooldown period (in seconds)
    function updateCooldownPeriod(uint256 newCooldownPeriod) public onlyOwner {
        require(cooldownPeriod != 0, "Farm doesnot support lockup");
        uint256 oldCooldownPeriod = cooldownPeriod;
        cooldownPeriod = newCooldownPeriod;
        emit CooldownPeriodUpdated(oldCooldownPeriod, cooldownPeriod);
    }

    /// @notice Pause / UnPause the deposit
    function toggleDepositPause() public onlyOwner {
        isPaused = !isPaused;
        emit DepositPaused(isPaused);
    }

    /// @notice Function to update reward params for a fund.
    /// @param fundId The id of the reward fund to be updated
    /// @param newRewardRate The new reward rate for the fund (includes the precision)
    function setRewardsPerSec(
        uint8 fundId,
        address rwdToken,
        uint256 newRewardRate
    ) public {
        require(
            _msgSender() == rewardData[rwdToken].tknManager,
            "Only manager can update reward params"
        );
        uint256 rwdId = rewardData[rwdToken].id;
        // Update the total accumulated rewards here
        _updateFarmRewardData();

        // Update the reward rate
        uint256 oldRewardRate = rewardFunds[fundId].rewardsPerSec[rwdId];
        rewardFunds[fundId].rewardsPerSec[rwdId] = newRewardRate;

        emit RewardRateUpdated(fundId, rwdToken, oldRewardRate, newRewardRate);
    }

    /// @notice Get the remaining reward balnce for the farm.
    /// @param rwdToken The reward token's address
    function getRewardBalance(address rwdToken) public view returns (uint256) {
        uint256 rwdId = rewardData[rwdToken].id;
        require(rwdId != 0, "Invalid rwdToken");

        uint256 numFunds = rewardFunds.length;
        uint256 rewardsAcc = rewardData[rwdToken].accRewards;
        if (block.timestamp > lastFundUpdateTime) {
            uint256 time = lastFundUpdateTime - block.timestamp;
            for (uint8 i = 0; i < rewardFunds.length; ++i) {
                rewardsAcc += rewardFunds[i].rewardsPerSec[rwdId] * time;
            }
        }
        return (rewardData[rwdToken].supply - rewardsAcc);
    }

    /// @notice Claim rewards for the user.
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @dev NOTE: any function calling this private
    ///     function should be marked as non-reentrant
    function _claimRewards(address account, uint256 depositId) private {
        _updateFarmRewardData();

        Deposit storage userDeposit = deposits[account][depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];

        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        uint256[] memory totalRewards = new uint256[](numRewards);
        // Compute the rewards for each subscription.
        for (uint8 i = 0; i < numSubs; ++i) {
            uint256[] memory rewards = new uint256[](numRewards);

            for (uint256 j = 0; j < numRewards; ++j) {
                // rewards = (liquidity * accRewardPerShare) / PREC - rewardDebt
                uint256 accRewards = (userDeposit.liquidity *
                    rewardFunds[depositSubs[i].fundId].accRewardPerShare[j]) /
                    PREC;
                rewards[j] = accRewards - depositSubs[i].rewardDebt[j];
                depositSubs[i].rewardClaimed[j] += rewards[j];
                totalRewards[j] += rewards[j];

                // Update userRewardDebt for the subscritption
                // rewardDebt = liquidity * accRewardPerShare
                depositSubs[i].rewardDebt[j] = accRewards;
            }

            emit RewardsClaimed(
                account,
                depositSubs[i].fundId,
                userDeposit.tokenId,
                userDeposit.liquidity,
                rewardFunds[depositSubs[i].fundId].totalLiquidity,
                rewards
            );
        }

        for (uint8 j = 0; j < numRewards; ++j) {
            // Update the total rewards earned for the deposit
            userDeposit.totalRewardsClaimed[j] += totalRewards[j];
        }

        if (inEmergency) {
            // Record event in case of emergency
            emit EmergencyClaim(account);
        } else {
            // Transfer the rewards to the user
            for (uint8 j = 0; j < numRewards; ++j) {
                IERC20(rewardTokens[j]).safeTransfer(account, totalRewards[j]);
            }
        }
    }

    /// @notice Add subscription to the reward fund for a deposit
    /// @param tokenId The tokenId of the deposit
    /// @param fundId The reward fund id
    /// @param liquidity The liquidity of the deposit
    function _subscribeRewardFund(
        uint8 fundId,
        uint256 tokenId,
        uint256 liquidity
    ) private {
        require(fundId < rewardFunds.length, "Invalid fund id");
        // Subscribe to the reward fund
        // initialize user's reward debt
        require(
            subscriptions[tokenId].length < 2,
            "Can't subscribe more than 2 funds"
        );
        uint256 numRewards = rewardTokens.length;
        subscriptions[tokenId].push(
            Subscription({
                fundId: fundId,
                rewardDebt: new uint256[](numRewards),
                rewardClaimed: new uint256[](numRewards)
            })
        );
        uint256 subId = subscriptions[tokenId].length - 1;
        for (uint8 i = 0; i < numRewards; ++i) {
            subscriptions[tokenId][subId].rewardDebt[i] =
                (liquidity * rewardFunds[fundId].accRewardPerShare[i]) /
                PREC;
        }

        rewardFunds[fundId].totalLiquidity += liquidity;
    }

    /// @notice Unsubscribe a reward fund from a deposit
    /// @param fundId The reward fund id
    /// @param account The user's address
    /// @param depositId The deposit id corresponding to the user
    /// @dev The rewards claimed from the reward fund is persisted in the event
    function _unsubscribeRewardFund(
        uint8 fundId,
        address account,
        uint256 depositId
    ) private {
        require(fundId < rewardFunds.length, "Invalid fund id");
        Deposit storage userDeposit = deposits[account][depositId];
        uint256 numRewards = rewardTokens.length;

        // Unsubscribe from the reward fund
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        uint256 numFunds = depositSubs.length;
        for (uint256 i = 0; i < numFunds; ++i) {
            if (depositSubs[i].fundId == fundId) {
                // Persist the reward information
                uint256[] memory rewardClaimed = new uint256[](numRewards);

                for (uint8 j = 0; j < numRewards; ++j) {
                    rewardClaimed[j] = depositSubs[i].rewardClaimed[j];
                }

                // Delete the subscription from the list
                depositSubs[i] = depositSubs[numFunds - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund
                rewardFunds[fundId].totalLiquidity -= userDeposit.liquidity;

                emit PoolUnsubscribed(
                    account,
                    userDeposit.tokenId,
                    fundId,
                    userDeposit.startTime,
                    block.timestamp,
                    rewardClaimed
                );

                break;
            }
        }
    }

    /// @notice Function to update the FarmRewardData for all funds
    function _updateFarmRewardData() private {
        if (
            block.timestamp > lastFundUpdateTime &&
            block.timestamp > farmStartTime
        ) {
            uint256 time = block.timestamp - lastFundUpdateTime;
            // Update the two reward funds.
            uint256 numRewards = rewardTokens.length;
            for (uint8 i = 0; i < rewardFunds.length; ++i) {
                RewardFund storage fund = rewardFunds[i];
                if (fund.totalLiquidity > 0) {
                    for (uint8 j = 0; j < numRewards; j++) {
                        rewardData[rewardTokens[j]].accRewards +=
                            fund.rewardsPerSec[j] *
                            time;
                        fund.accRewardPerShare[j] +=
                            (fund.rewardsPerSec[j] * time * PREC) /
                            fund.totalLiquidity;
                    }
                }
            }
            lastFundUpdateTime = block.timestamp;
        }
    }

    /// @notice Function to setup the reward funds during construction.
    /// @param numFunds - Number of reward funds to setup.
    /// @param _rewardData - Reward data for each reward token.
    function _setupRewardFunds(
        uint8 numFunds,
        RewardTokenData[] memory _rewardData
    ) private {
        // Setup reward related information.
        uint256 numRewards = _rewardData.length;
        require(numRewards > 0 && numRewards <= 2, "Invalid reward data");

        // Initialilze fund storage
        for (uint8 i = 0; i < numFunds; ++i) {
            RewardFund memory _rewardFund = RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: new uint256[](numRewards),
                accRewardPerShare: new uint256[](numRewards)
            });
            rewardFunds.push(_rewardFund);
        }

        // Initialize reward Data
        rewardTokens = new address[](numRewards);
        for (uint8 i = 0; i < numRewards; ++i) {
            address rwdToken = _rewardData[i].token;
            // Validate if addresses are correct
            _isNonZeroAddr(_rewardData[i].token);
            _isNonZeroAddr(_rewardData[i].tknManager);
            _isNonZeroAddr(_rewardData[i].emergencyReturn);
            for (uint8 j = 0; j < numFunds; ++j) {
                // @dev assign the relavant reward rates to the funds
                rewardFunds[j].rewardsPerSec[i] = _rewardData[i].rewardsPerSec[
                    j
                ];
            }
            rewardTokens[i] = rwdToken;
            rewardData[rwdToken] = RewardData({
                id: i + 1,
                tknManager: _rewardData[i].tknManager,
                emergencyReturn: _rewardData[i].emergencyReturn,
                accRewards: 0,
                supply: 0
            });
        }
    }

    /// @notice Validate the position for the pool and get Liquidity
    /// @param tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 tokenId) private view returns (uint256) {
        /// @dev Get the info of the required token
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = INFPM(NFPM).positions(tokenId);

        /// @dev Check if the token belongs to correct pool
        require(
            uniswapPool ==
                IUniswapV3Factory(UNIV3_FACTORY).getPool(token0, token1, fee),
            "Incorrect pool token"
        );

        /// @dev Check if the token adheres to the tick range
        require(
            tickLower == tickLowerAllowed && tickUpper == tickUpperAllowed,
            "Incorrect tick range"
        );

        return uint256(liquidity);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
