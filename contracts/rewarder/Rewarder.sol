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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFarm} from "../interfaces/IFarm.sol";
import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";

/// @title Rewarder contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract tracks farms, their APR and other data for a specific reward token.
/// @dev Farms for UniV3 pools using Rewarder contract must have a minimum observationCardinality of 20.
///      It can be updated by calling increaseObservationCardinalityNext function on the pool.
contract Rewarder is Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // rewardRate - Amount of tokens emitted per second.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseAssetIndexes - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FarmRewardConfig {
        uint256 apr;
        uint256 rewardRate;
        uint256 maxRewardRate;
        uint256[] baseAssetIndexes;
        uint256 nonLockupRewardPer; // 5e3 = 50%.
    }

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseTokens - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FarmRewardConfigInput {
        uint256 apr;
        uint256 maxRewardRate;
        address[] baseTokens;
        uint256 nonLockupRewardPer; // 5e3 = 50%.
    }

    uint256 public constant MAX_PERCENTAGE = 1e4;
    uint256 public constant APR_PRECISION = 1e8; // 1%.
    uint256 public constant REWARD_PERIOD = 1 weeks;
    uint256 public constant DENOMINATOR = 100;
    uint256 public constant ONE_YEAR = 365 days;
    address public REWARD_TOKEN; // solhint-disable-line var-name-mixedcase
    uint8 public REWARD_TOKEN_DECIMALS; // solhint-disable-line var-name-mixedcase
    uint256 public totalRewardRate; // Rewards emitted per second for all the farms from this rewarder.
    address public rewarderFactory;
    // farm -> FarmRewardConfig.
    mapping(address => FarmRewardConfig) public farmRewardConfigs;
    mapping(address => bool) public calibrationRestricted;
    mapping(address => uint8) private _decimals;

    // Events.
    event RewardConfigUpdated(address indexed farm, FarmRewardConfigInput rewardConfig);
    event APRUpdated(address indexed farm, uint256 apr);
    event RewardCalibrated(address indexed farm, uint256 rewardsSent, uint256 rewardRate);
    event CalibrationRestrictionToggled(address indexed farm);

    // Custom Errors.
    error InvalidAddress();
    error InvalidFarm();
    error FarmNotConfigured(address farm);
    error ZeroAmount();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);
    error CalibrationRestricted(address farm);

    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initializer function of this contract.
    /// @param _rwdToken Address of the reward token.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    function initialize(address _rwdToken, address _oracle, address _admin) external initializer {
        _initialize(_rwdToken, _oracle, _admin, msg.sender);
    }

    /// @notice Function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateReward(address _farm) external nonReentrant returns (uint256 rewardsToSend) {
        _isConfigured(_farm);
        if (calibrationRestricted[_farm] && msg.sender != owner()) {
            revert CalibrationRestricted(_farm);
        }
        return _calibrateReward(_farm);
    }

    /// @notice Function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerOfFarm(address _farm, address _newManager) external onlyOwner {
        _validateNonZeroAddr(_farm);
        IFarm(_farm).updateRewardData(REWARD_TOKEN, _newManager);
    }

    /// @notice Function to recover reward funds from the farm.
    /// @param _farm Farm's address from which reward funds is to be recovered.
    /// @param _amount Amount which is to be recovered.
    function recoverRewardFundsOfFarm(address _farm, uint256 _amount) external onlyOwner {
        _validateNonZeroAddr(_farm);
        IFarm(_farm).recoverRewardFunds(REWARD_TOKEN, _amount);
    }

    /// @notice Function to update APR.
    /// @param _farm Address of the farm.
    /// @param _apr APR in 1e8 precision.
    function updateAPR(address _farm, uint256 _apr) external onlyOwner nonReentrant {
        _isConfigured(_farm);
        farmRewardConfigs[_farm].apr = _apr;
        emit APRUpdated(_farm, _apr);
        _calibrateReward(_farm);
    }

    /// @notice Function to toggle calibration restriction.
    /// @param _farm Address of farm for which calibration restriction is to be toggled.
    function toggleCalibrationRestriction(address _farm) external onlyOwner {
        calibrationRestricted[_farm] = !calibrationRestricted[_farm];
        emit CalibrationRestrictionToggled(_farm);
    }

    /// @notice Function to recover ERC20 tokens from this contract.
    /// @param _token Address of the token.
    /// @param _amount Amount of the tokens.
    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        if (IERC20(_token).balanceOf(address(this)) == 0) {
            revert ZeroAmount();
        }
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice Function to get token amounts value of underlying pool of the farm.
    /// @param _farm Address of the farm.
    /// @return Array of token addresses.
    /// @return Array of token amounts.
    function getTokenAmounts(address _farm) external view returns (address[] memory, uint256[] memory) {
        return _getTokenAmounts(_farm);
    }

    /// @notice Function to get reward config for a farm.
    /// @param _farm Address of the farm.
    /// @return FarmRewardConfig Farm reward config.
    function getFarmRewardConfig(address _farm) external view returns (FarmRewardConfig memory) {
        _isConfigured(_farm);
        return farmRewardConfigs[_farm];
    }

    /// @notice Function to calculate the time till which rewards are there for an LP.
    /// @param _farm Address of the farm for which the end time is to be calculated.
    /// @return rewardsEndingOn Timestamp in seconds till which the rewards are there in farm and in rewarder.
    function rewardsEndTime(address _farm) external view returns (uint256 rewardsEndingOn) {
        uint256 farmBalance = IFarm(_farm).getRewardBalance(REWARD_TOKEN);
        uint256 rewarderBalance = IERC20(REWARD_TOKEN).balanceOf(address(this));
        rewardsEndingOn = block.timestamp
            + ((farmBalance / farmRewardConfigs[_farm].rewardRate) + (rewarderBalance / totalRewardRate));
    }

    /// @notice Function to update the REWARD_TOKEN configuration.
    ///         This function calibrates reward so token manager must be updated to address of this contract in the farm.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, FarmRewardConfigInput memory _rewardConfig)
        public
        onlyOwner
        nonReentrant
    {
        if (!_isValidFarm(_farm, _rewardConfig.baseTokens)) {
            revert InvalidFarm();
        }
        address oracle = IRewarderFactory(rewarderFactory).oracle();
        // validating new reward config.
        uint256 baseTokensLen = _rewardConfig.baseTokens.length;
        for (uint256 i; i < baseTokensLen;) {
            _validatePriceFeed(_rewardConfig.baseTokens[i], oracle);
            unchecked {
                ++i;
            }
        }
        _validateRewardPer(_rewardConfig.nonLockupRewardPer);
        farmRewardConfigs[_farm].apr = _rewardConfig.apr;
        farmRewardConfigs[_farm].maxRewardRate = _rewardConfig.maxRewardRate;
        farmRewardConfigs[_farm].nonLockupRewardPer = _rewardConfig.nonLockupRewardPer;
        emit RewardConfigUpdated(_farm, _rewardConfig);
    }

    /// @notice Internal initialize function.
    /// @param _rwdToken Address of the reward token.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    /// @param _rewarderFactory Address of Rewarder factory contract.
    function _initialize(address _rwdToken, address _oracle, address _admin, address _rewarderFactory) internal {
        _validatePriceFeed(_rwdToken, _oracle);
        rewarderFactory = _rewarderFactory;
        REWARD_TOKEN = _rwdToken;
        REWARD_TOKEN_DECIMALS = ERC20(_rwdToken).decimals();
        _validateNonZeroAddr(_admin);
        _transferOwnership(_admin);
    }

    /// @notice Function to check if the farm's reward is configured.
    /// @param _farm Address of the farm.
    function _isConfigured(address _farm) internal view {
        if (farmRewardConfigs[_farm].baseAssetIndexes.length == 0) {
            revert FarmNotConfigured(_farm);
        }
    }

    /// @notice An internal function to get token amounts for the farm.
    /// @param _farm Address of the farm.
    /// @return Array of token addresses.
    /// @return Array of token amounts.
    function _getTokenAmounts(address _farm) internal view virtual returns (address[] memory, uint256[] memory) {
        return IFarm(_farm).getTokenAmounts();
    }

    /// @notice Function to check if the reward token of this contract is one of farm's reward token.
    /// @param _farm Address of the farm.
    /// @return If farm has one of the reward token as reward token of this contract.
    function _hasRewardToken(address _farm) internal view virtual returns (bool) {
        address[] memory rwdTokens = IFarm(_farm).getRewardTokens();
        uint256 rwdTokensLen = rwdTokens.length;
        for (uint8 i; i < rwdTokensLen;) {
            if (rwdTokens[i] == REWARD_TOKEN) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Validate address.
    /// @param _addr Address to be validated.
    function _validateNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }

    function _calibrateReward(address _farm) private returns (uint256 rewardsToSend) {
        FarmRewardConfig memory farmRewardConfig = farmRewardConfigs[_farm];
        uint256 rewardRate;
        if (farmRewardConfig.apr != 0) {
            (address[] memory assets, uint256[] memory amounts) = _getTokenAmounts(_farm);
            // Calculating total USD value for all the assets.
            uint256 totalValue;
            uint256 baseTokensLen = farmRewardConfig.baseAssetIndexes.length;
            IOracle.PriceData memory priceData;
            address oracle = IRewarderFactory(rewarderFactory).oracle();
            for (uint8 i; i < baseTokensLen;) {
                priceData = _getPrice(assets[farmRewardConfig.baseAssetIndexes[i]], oracle);
                totalValue += (
                    priceData.price
                        * _normalizeAmount(
                            assets[farmRewardConfig.baseAssetIndexes[i]], amounts[farmRewardConfig.baseAssetIndexes[i]]
                        )
                ) / priceData.precision;
                unchecked {
                    ++i;
                }
            }
            // Getting reward token price to calculate rewards emission.
            priceData = _getPrice(REWARD_TOKEN, oracle);

            // For token with lower decimals the calculation of rewardRate might not be accurate because of precision loss in truncation.
            // rewardValuePerSecond = (APR * totalValue / 100) / 365 days.
            // rewardRate = rewardValuePerSecond * pricePrecision / price.
            rewardRate = (farmRewardConfig.apr * totalValue * priceData.precision)
                / (APR_PRECISION * DENOMINATOR * ONE_YEAR * priceData.price);

            if (rewardRate > farmRewardConfig.maxRewardRate) {
                rewardRate = farmRewardConfig.maxRewardRate;
            }
            // Calculating the deficit rewards in farm and sending them.
            uint256 _farmRwdBalance = IFarm(_farm).getRewardBalance(REWARD_TOKEN);
            uint256 _rewarderRwdBalance = IERC20(REWARD_TOKEN).balanceOf(address(this));
            rewardsToSend = rewardRate * REWARD_PERIOD;
            if (rewardsToSend > _farmRwdBalance) {
                rewardsToSend -= _farmRwdBalance;
                if (rewardsToSend > _rewarderRwdBalance) {
                    rewardsToSend = _rewarderRwdBalance;
                }
            } else {
                rewardsToSend = 0;
            }
        } else {
            rewardRate = 0;
            farmRewardConfigs[_farm].rewardRate = 0;
            rewardsToSend = 0;
        }
        // Updating reward rate in farm and adjusting global reward rate of this rewarder.
        _adjustGlobalRewardRate(farmRewardConfig.rewardRate, rewardRate);
        farmRewardConfigs[_farm].rewardRate = rewardRate;
        emit RewardCalibrated(_farm, rewardsToSend, rewardRate);
        _setRewardRate(_farm, rewardRate, farmRewardConfig.nonLockupRewardPer);
        if (rewardsToSend != 0) IERC20(REWARD_TOKEN).safeTransfer(_farm, rewardsToSend);
    }

    /// @notice Function to set reward rate in the farm.
    /// @param _farm Address of the farm.
    /// @param _rwdRate Reward per second to be emitted.
    /// @param _nonLockupRewardPer Reward percentage to be allocated to no lockup fund.
    function _setRewardRate(address _farm, uint256 _rwdRate, uint256 _nonLockupRewardPer) private {
        uint256[] memory _newRewardRates;
        if (IFarm(_farm).cooldownPeriod() == 0) {
            _newRewardRates = new uint256[](1);
            _newRewardRates[0] = _rwdRate;
            IFarm(_farm).setRewardRate(REWARD_TOKEN, _newRewardRates);
        } else {
            _newRewardRates = new uint256[](2);
            uint256 commonFundShare = (_rwdRate * _nonLockupRewardPer) / MAX_PERCENTAGE;
            _newRewardRates[0] = commonFundShare;
            _newRewardRates[1] = _rwdRate - commonFundShare;
            IFarm(_farm).setRewardRate(REWARD_TOKEN, _newRewardRates);
        }
    }

    /// @notice Function to adjust global rewards per second emitted for a reward token.
    /// @param _oldRewardRate Old emission rate.
    /// @param _newRewardRate New emission rate.
    function _adjustGlobalRewardRate(uint256 _oldRewardRate, uint256 _newRewardRate) private {
        totalRewardRate = totalRewardRate - _oldRewardRate + _newRewardRate;
    }

    /// @notice Function to validate farm.
    /// @param _farm Address of the farm to be validated.
    /// @param _baseTokens Array of base tokens.
    /// @return bool True if farm is valid.
    /// @dev It checks that the farm should implement getTokenAmounts and have REWARD_TOKEN.
    /// as one of the reward tokens.
    function _isValidFarm(address _farm, address[] memory _baseTokens) private returns (bool) {
        return _hasRewardToken(_farm) && _hasBaseTokens(_farm, _baseTokens);
    }

    /// @notice Function to check whether the base tokens are a subset of farm's assets.
    /// @param _farm Address of the farm.
    /// @param _baseTokens Array of base token addresses to be considered for value calculation.
    /// @dev It handles repeated base tokens as well and pushes indexed in farmRewardConfigs.
    /// @return hasBaseTokens True if baseTokens are non redundant and are a subset of assets.
    function _hasBaseTokens(address _farm, address[] memory _baseTokens) private returns (bool) {
        (address[] memory _assets,) = _getTokenAmounts(_farm);
        uint256 _assetsLen = _assets.length;
        uint256 _baseTokensLen = _baseTokens.length;
        bool hasBaseTokens;
        for (uint8 i; i < _baseTokensLen;) {
            hasBaseTokens = false;
            for (uint8 j; j < _assetsLen;) {
                if (_baseTokens[i] == _assets[j]) {
                    _decimals[_baseTokens[i]] = ERC20(_baseTokens[i]).decimals();
                    hasBaseTokens = true;
                    farmRewardConfigs[_farm].baseAssetIndexes.push(j);
                    // Deleting will make _assets[j] -> 0x0 so if _baseTokens have repeated address, this function will return false.
                    delete _assets[j];
                    break;
                }
                unchecked {
                    ++j;
                }
            }
            if (!hasBaseTokens) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Function to normalize asset amounts to be of precision REWARD_TOKEN_DECIMALS.
    /// @param _token Address of the asset token.
    /// @param _amount Amount of the token.
    /// @return Normalized amount of the token in _desiredPrecision.
    function _normalizeAmount(address _token, uint256 _amount) private view returns (uint256) {
        uint8 decimals = _decimals[_token];
        uint8 rwdTokenDecimals = REWARD_TOKEN_DECIMALS;
        if (decimals < rwdTokenDecimals) {
            return _amount * 10 ** (rwdTokenDecimals - decimals);
        }
        if (decimals > rwdTokenDecimals) {
            return _amount / 10 ** (decimals - rwdTokenDecimals);
        }
        return _amount;
    }

    /// @notice Function to fetch and get the price of a token.
    /// @param _token Token for which the the price is to be fetched.
    /// @param _oracle Address of the oracle contract.
    /// @return priceData Price data of the token.
    function _getPrice(address _token, address _oracle) private view returns (IOracle.PriceData memory priceData) {
        priceData = IOracle(_oracle).getPrice(_token);
    }

    /// @notice Function to validate price feed.
    /// @param _token Token to be validated.
    /// @param _oracle Address of the oracle.
    function _validatePriceFeed(address _token, address _oracle) private view {
        if (!IOracle(_oracle).priceFeedExists(_token)) {
            revert PriceFeedDoesNotExist(_token);
        }
    }

    /// @notice Function to validate the no lockup fund's reward percentage.
    /// @param _percentage No lockup fund's reward percentage to be validated.
    function _validateRewardPer(uint256 _percentage) private pure {
        if (_percentage == 0 || _percentage > MAX_PERCENTAGE) {
            revert InvalidRewardPercentage(_percentage);
        }
    }
}
