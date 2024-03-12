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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFarm} from "../interfaces/IFarm.sol";
import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";

/// @title Rewarder contract of Demeter Protocol.
/// @notice This contract tracks farms, their APR and other data for a specific reward token.
/// @author Sperax Foundation.
contract Rewarder is Ownable, Initializable {
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
        uint256 noLockupRewardPer; // 5000 = 50%
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
        uint256 noLockupRewardPer; // 5000 = 50%
    }

    uint256 public constant MAX_PERCENTAGE = 10000;
    uint256 public constant APR_PRECISION = 1e8; // 1%
    uint256 public constant REWARD_PERIOD = 1 weeks;
    address public REWARD_TOKEN;
    uint256 public totalRewardRate; // Rewards emitted per second for all the farms from this rewarder.
    address public rewarderFactory;
    // farm -> FarmRewardConfig
    mapping(address => FarmRewardConfig) public farmRewardConfigs;
    mapping(address => uint8) private _decimals;

    event RewardConfigUpdated(address indexed farm, FarmRewardConfigInput rewardConfig);
    event RewardCalibrated(address indexed farm, uint256 rewardsSent, uint256 rewardRate);

    error InvalidAddress();
    error InvalidFarm();
    error ZeroAmount();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);

    /// @notice Initializer function of this contract.
    /// @param _rwdToken Address of the reward token.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    function initialize(address _rwdToken, address _oracle, address _admin) external initializer {
        _initialize(_rwdToken, _oracle, _admin, msg.sender);
    }

    /// @notice A function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerInFarm(address _farm, address _newManager) external onlyOwner {
        IFarm(_farm).updateRewardData(REWARD_TOKEN, _newManager);
    }

    /// @notice A function to recover ERC20 tokens from this contract.
    /// @param _token Address of the token.
    /// @param _amount Amount of the tokens.
    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        if (IERC20(_token).balanceOf(address(this)) == 0) {
            revert ZeroAmount();
        }
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice A function to get reward config for a farm.
    /// @param _farm Address of the farm.
    function getFarmRewardConfig(address _farm) external view returns (FarmRewardConfig memory) {
        // @todo Add a validation to check farm is configured.
        return farmRewardConfigs[_farm];
    }

    /// @notice A function to calculate the time till which rewards are there for an LP.
    /// @param _farm Address of the farm for which the end time is to be calculated.
    /// @return rewardsEndingOn Timestamp in seconds till which the rewards are there in farm and in rewarder.
    function rewardsEndTime(address _farm) external view returns (uint256 rewardsEndingOn) {
        uint256 farmBalance = IERC20(REWARD_TOKEN).balanceOf(_farm);
        uint256 rewarderBalance = IERC20(REWARD_TOKEN).balanceOf(address(this));
        rewardsEndingOn = block.timestamp
            + ((farmBalance / farmRewardConfigs[_farm].rewardRate) + (rewarderBalance / totalRewardRate));
    }

    // @todo add updateApr function
    /// @notice A function to update the REWARD_TOKEN configuration.
    ///         This function calibrates reward so token manager must be updated to address of this in the farm.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, FarmRewardConfigInput memory _rewardConfig) public onlyOwner {
        if (!_isValidFarm(_farm, _rewardConfig.baseTokens)) {
            revert InvalidFarm();
        }
        address oracle = IRewarderFactory(rewarderFactory).oracle();
        // validating new reward config
        uint256 baseTokensLen = _rewardConfig.baseTokens.length;
        for (uint256 i; i < baseTokensLen;) {
            _validatePriceFeed(_rewardConfig.baseTokens[i], oracle);
            unchecked {
                ++i;
            }
        }
        _validateRewardPer(_rewardConfig.noLockupRewardPer);
        farmRewardConfigs[_farm].apr = _rewardConfig.apr;
        farmRewardConfigs[_farm].maxRewardRate = _rewardConfig.maxRewardRate;
        farmRewardConfigs[_farm].noLockupRewardPer = _rewardConfig.noLockupRewardPer;
        emit RewardConfigUpdated(_farm, _rewardConfig);
    }

    /// @notice A function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateReward(address _farm) public returns (uint256 rewardsToSend) {
        FarmRewardConfig memory farmRewardConfig = farmRewardConfigs[_farm];
        if (farmRewardConfig.apr != 0) {
            (address[] memory assets, uint256[] memory amounts) = _getTokenAmounts(_farm);
            // Calculating total USD value for all the assets.
            uint256 totalValue;
            uint256 baseTokensLen = farmRewardConfig.baseAssetIndexes.length;
            IOracle.PriceData memory _priceData;
            address oracle = IRewarderFactory(rewarderFactory).oracle();
            for (uint8 i; i < baseTokensLen;) {
                _priceData = _getPrice(assets[farmRewardConfig.baseAssetIndexes[i]], oracle);
                totalValue += (
                    _priceData.price
                        * _normalizeAmount(
                            assets[farmRewardConfig.baseAssetIndexes[i]], amounts[farmRewardConfig.baseAssetIndexes[i]]
                        )
                ) / _priceData.precision;
                unchecked {
                    ++i;
                }
            }
            // Getting reward token price to calculate rewards emission.
            _priceData = _getPrice(REWARD_TOKEN, oracle);
            uint256 rewardRate = (
                (((farmRewardConfig.apr * totalValue) / (APR_PRECISION * 100)) / 365 days) * _priceData.precision
            ) / _priceData.price;
            if (rewardRate > farmRewardConfig.maxRewardRate) {
                rewardRate = farmRewardConfig.maxRewardRate;
            }
            // Calculating the deficit rewards in farm and sending them.
            uint256 _farmRwdBalance = IERC20(REWARD_TOKEN).balanceOf(_farm);
            uint256 _rewarderRwdBalance = IERC20(REWARD_TOKEN).balanceOf(address(this));
            rewardsToSend = (rewardRate * REWARD_PERIOD);
            if (rewardsToSend > _farmRwdBalance) {
                rewardsToSend -= _farmRwdBalance;
                if (rewardsToSend > _rewarderRwdBalance) {
                    rewardsToSend = _rewarderRwdBalance;
                }
                IERC20(REWARD_TOKEN).safeTransfer(_farm, rewardsToSend);
            } else {
                rewardsToSend = 0;
            }
            // Updating reward rate in farm and adjusting global reward rate of this rewarder.
            _setRewardRate(_farm, rewardRate, farmRewardConfig.noLockupRewardPer);
            _adjustGlobalRewardRate(farmRewardConfig.rewardRate, rewardRate);
            farmRewardConfigs[_farm].rewardRate = rewardRate;
            emit RewardCalibrated(_farm, rewardsToSend, rewardRate);
        } else {
            _setRewardRate(_farm, 0, farmRewardConfig.noLockupRewardPer);
            _adjustGlobalRewardRate(farmRewardConfig.rewardRate, 0);
            farmRewardConfigs[_farm].rewardRate = 0;
            emit RewardCalibrated(_farm, 0, 0);
        }
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
        _validateNonZeroAddr(_admin);
        _transferOwnership(_admin);
    }

    /// @notice An internal function to get token amounts for the farm.
    /// @param _farm Address of the farm.
    function _getTokenAmounts(address _farm) internal view virtual returns (address[] memory, uint256[] memory) {
        return IFarm(_farm).getTokenAmounts();
    }

    /// @notice A function to check the reward token of this is a farm's reward token.
    /// @param _farm Address of the farm.
    /// @return If farm has one of the reward token as reward token of this.
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

    /// @notice A function to set reward rate in the farm.
    /// @param _farm Address of the farm.
    /// @param _rwdRate Reward per second to be emitted.
    /// @param _noLockupRewardPer Reward percentage to be allocated to no lockup fund
    function _setRewardRate(address _farm, uint256 _rwdRate, uint256 _noLockupRewardPer) private {
        uint256[] memory _newRewardRates;
        if (IFarm(_farm).cooldownPeriod() == 0) {
            _newRewardRates = new uint256[](1);
            _newRewardRates[0] = _rwdRate;
            IFarm(_farm).setRewardRate(REWARD_TOKEN, _newRewardRates);
        } else {
            _newRewardRates = new uint256[](2);
            uint256 commonFundShare = (_rwdRate * _noLockupRewardPer) / MAX_PERCENTAGE;
            _newRewardRates[0] = commonFundShare;
            _newRewardRates[1] = _rwdRate - commonFundShare;
            IFarm(_farm).setRewardRate(REWARD_TOKEN, _newRewardRates);
        }
    }

    /// @notice A function to adjust global rewards per second emitted for a reward token.
    /// @param _oldRewardRate Old emission rate.
    /// @param _newRewardRate New emission rate.
    function _adjustGlobalRewardRate(uint256 _oldRewardRate, uint256 _newRewardRate) private {
        totalRewardRate -= _oldRewardRate;
        totalRewardRate += _newRewardRate;
    }

    /// @notice A function to normalize asset amounts to be of precision 1e18.
    /// @param _token Address of the asset token.
    /// @param _amount Amount of the token.
    /// @return Normalized amount of the token in 1e18.
    function _normalizeAmount(address _token, uint256 _amount) private returns (uint256) {
        if (_decimals[_token] == 0) {
            _decimals[_token] = ERC20(_token).decimals();
        }
        _amount *= 10 ** (18 - _decimals[_token]);
        return _amount;
    }

    /// @notice A function to validate farm.
    /// @param _farm Address of the farm to be validated.
    /// @dev It checks that the farm should implement getTokenAmounts and have REWARD_TOKEN
    /// as one of the reward tokens.
    function _isValidFarm(address _farm, address[] memory _baseTokens) private returns (bool) {
        return _hasRewardToken(_farm) && _hasBaseTokens(_farm, _baseTokens);
    }

    /// @notice A function to check whether the base tokens are a subset of farm's assets.
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

    /// @notice A function to fetch and get the price of a token.
    /// @param _token Token for which the the price is to be fetched.
    /// @param _oracle Address of the oracle contract.
    function _getPrice(address _token, address _oracle) private view returns (IOracle.PriceData memory _priceData) {
        _priceData = IOracle(_oracle).getPrice(_token);
    }

    /// @notice A function to validate price feed.
    /// @param _token Token to be validated.
    /// @param _oracle Address of the oracle.
    function _validatePriceFeed(address _token, address _oracle) private view {
        if (!IOracle(_oracle).priceFeedExists(_token)) {
            revert PriceFeedDoesNotExist(_token);
        }
    }

    /// @notice A function to validate the no lockup fund's reward percentage.
    /// @param _percentage No lockup fund's reward percentage to be validated.
    function _validateRewardPer(uint256 _percentage) private pure {
        if (_percentage == 0 || _percentage > MAX_PERCENTAGE) {
            revert InvalidRewardPercentage(_percentage);
        }
    }
}
