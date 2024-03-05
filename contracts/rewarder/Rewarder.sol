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

/// @title Rewarder contract of Demeter Protocol
/// @notice This contract tracks farms, their APR, and rewards
/// @author Sperax Foundation
contract Rewarder is Ownable, Initializable {
    using SafeERC20 for IERC20;

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // rewardsPerSec - Amount of tokens emitted per second.
    // maxRewardsPerSec - Maximum amount of tokens to be emitted per second.
    // baseTokens - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FixedAPRRewardConfig {
        uint256 apr;
        uint256 rewardsPerSec;
        uint256 maxRewardsPerSec;
        address[] baseTokens;
        uint256 noLockupRewardPer; // 5000 = 50%
    }

    uint256 public constant MAX_PERCENTAGE = 10000;
    uint256 public constant APR_PRECISION = 1e8;
    uint256 public totalRewardsPerSec;
    address public rewarderFactory;
    address public rewardToken;
    // farm -> FixedAPRRewardConfig
    mapping(address => FixedAPRRewardConfig) public farmRewardConfigs;
    mapping(address => uint8) private _decimals;

    event RewardConfigUpdated(address indexed farm, FixedAPRRewardConfig rewardConfig);
    event RewardTokenCalibrated(address indexed farm, uint256 rewardsSent, uint256 rewardsPerSecond);

    error InvalidAddress();
    error InvalidFarm();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);

    /// @notice Initializer function of this contract.
    /// @param _rwdToken Address of the reward token.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    function initialize(address _rwdToken, address _oracle, address _admin) external initializer {
        _validatePriceFeed(_rwdToken, _oracle);
        rewarderFactory = msg.sender;
        rewardToken = _rwdToken;
        _transferOwnership(_admin);
    }

    /// @notice A function to update the rewardToken configuration.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, FixedAPRRewardConfig memory _rewardConfig) external onlyOwner {
        if (!_isValidFarm(_farm)) {
            revert InvalidFarm();
        }
        address _oracle = IRewarderFactory(rewarderFactory).oracle();
        // validating new reward config
        uint256 baseTokensLen = _rewardConfig.baseTokens.length;
        for (uint256 i; i < baseTokensLen;) {
            _validatePriceFeed(_rewardConfig.baseTokens[i], _oracle);
            unchecked {
                ++i;
            }
        }
        _validateRewardPer(_rewardConfig.noLockupRewardPer);
        _rewardConfig.rewardsPerSec = 0;
        farmRewardConfigs[_farm] = _rewardConfig;
        emit RewardConfigUpdated(_farm, _rewardConfig);
    }

    /// @notice A function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateRewards(address _farm) external returns (uint256 rewardsToSend) {
        FixedAPRRewardConfig memory farmRewardConfig = farmRewardConfigs[_farm];
        if (farmRewardConfig.apr != 0 && IFarm(_farm).isFarmActive()) {
            (address[] memory _assets, uint256[] memory _amounts) = IFarm(_farm).getTokenAmounts();
            uint256 _assetsLen = _assets.length;
            // Calculating total USD value for all the assets.
            uint256 totalValue;
            uint256 baseTokensLen = farmRewardConfig.baseTokens.length;
            IOracle.PriceData memory _priceData;
            address _oracle = IRewarderFactory(rewarderFactory).oracle();
            for (uint8 iFarmTokens; iFarmTokens < _assetsLen;) {
                for (uint8 jBaseTokens; jBaseTokens < baseTokensLen;) {
                    if (_assets[iFarmTokens] == farmRewardConfig.baseTokens[jBaseTokens]) {
                        _priceData = _getPrice(_assets[iFarmTokens], _oracle);
                        totalValue += (_priceData.price * _normalizeAmount(_assets[iFarmTokens], _amounts[iFarmTokens]))
                            / _priceData.precision;
                        break;
                    }
                    unchecked {
                        ++jBaseTokens;
                    }
                }
                unchecked {
                    ++iFarmTokens;
                }
            }
            // Getting reward token price to calculate rewards emission.
            _priceData = _getPrice(rewardToken, _oracle);
            uint256 rewardsPerSecond = (
                (((farmRewardConfig.apr * totalValue) / (APR_PRECISION * 100)) / 365 days) * _priceData.precision
            ) / _priceData.price;
            if (rewardsPerSecond > farmRewardConfig.maxRewardsPerSec) {
                rewardsPerSecond = farmRewardConfig.maxRewardsPerSec;
            }
            // Calculating the deficit rewards in farm and sending them.
            uint256 _farmRwdBalance = IERC20(rewardToken).balanceOf(_farm);
            uint256 _rewarderRwdBalance = IERC20(rewardToken).balanceOf(address(this));
            rewardsToSend = (rewardsPerSecond * 1 weeks);
            if (rewardsToSend > _farmRwdBalance) {
                rewardsToSend -= _farmRwdBalance;
                if (rewardsToSend > _rewarderRwdBalance) {
                    rewardsToSend = _rewarderRwdBalance;
                    rewardsPerSecond = (_farmRwdBalance + _rewarderRwdBalance) / 1 weeks;
                }
                IERC20(rewardToken).safeTransfer(_farm, rewardsToSend);
            } else {
                rewardsToSend = 0;
            }
            // Updating reward rate in farm and adjusting global reward rate of this rewarder.
            _setRewardRate(_farm, rewardsPerSecond, farmRewardConfig.noLockupRewardPer);
            _adjustGlobalRewardsPerSec(farmRewardConfig.rewardsPerSec, rewardsPerSecond);
            farmRewardConfigs[_farm].rewardsPerSec = rewardsPerSecond;
            emit RewardTokenCalibrated(_farm, rewardsToSend, rewardsPerSecond);
        }
    }

    /// @notice A function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerInFarm(address _farm, address _newManager) external onlyOwner {
        IFarm(_farm).updateRewardData(rewardToken, _newManager);
    }

    /// @notice A function to calculate the time till which rewards are there for an LP.
    /// @param _farm Address of the farm for which the end time is to be calculated.
    /// @return rewardsEndingOn Timestamp in seconds till which the rewards are there in farm and in rewarder.
    function rewardsEndTime(address _farm) external view returns (uint256 rewardsEndingOn) {
        uint256 farmBalance = IERC20(rewardToken).balanceOf(_farm);
        uint256 rewarderBalance = IERC20(rewardToken).balanceOf(address(this));
        rewardsEndingOn = block.timestamp
            + ((farmBalance / farmRewardConfigs[_farm].rewardsPerSec) + (rewarderBalance / totalRewardsPerSec));
    }

    /// @notice A function to set reward rate in the farm.
    /// @param _farm Address of the farm.
    /// @param _rwdPerSec Reward per second to be emitted.
    /// @param _noLockupRewardPer Reward percentage to be allocated to no lockup fund
    function _setRewardRate(address _farm, uint256 _rwdPerSec, uint256 _noLockupRewardPer) private {
        uint256[] memory _newRewardRates;
        if (IFarm(_farm).cooldownPeriod() == 0) {
            _newRewardRates = new uint256[](1);
            _newRewardRates[0] = _rwdPerSec;
            IFarm(_farm).setRewardRate(rewardToken, _newRewardRates);
        } else {
            _newRewardRates = new uint256[](2);
            uint256 commonFundShare = (_rwdPerSec * _noLockupRewardPer) / MAX_PERCENTAGE;
            _newRewardRates[0] = commonFundShare;
            _newRewardRates[1] = _rwdPerSec - commonFundShare;
            IFarm(_farm).setRewardRate(rewardToken, _newRewardRates);
        }
    }

    /// @notice A function to adjust global rewards per second emitted for a reward token.
    /// @param _oldRewardsPerSec Old emission rate.
    /// @param _newRewardsPerSecond New emission rate.
    function _adjustGlobalRewardsPerSec(uint256 _oldRewardsPerSec, uint256 _newRewardsPerSecond) private {
        totalRewardsPerSec -= _oldRewardsPerSec;
        totalRewardsPerSec += _newRewardsPerSecond;
    }

    /// @notice A function to normalize asset amounts to be of precision 1e18.
    /// @param _token Address of the asset token.
    /// @param _amount Amount of the token.
    /// @return Normalized amount of the token in 1e18.
    function _normalizeAmount(address _token, uint256 _amount) private returns (uint256) {
        if (_decimals[_token] == 0) {
            _decimals[_token] = ERC20(_token).decimals();
        }
        if (_decimals[_token] != 18) {
            _amount *= 10 ** (18 - _decimals[_token]);
        }
        return _amount;
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

    /// @notice A function to validate farm.
    /// @param _farm Address of the farm to be validated.
    /// @dev It checks that the farm should implement getTokenAmounts and have rewardToken
    /// as one of the reward tokens.
    function _isValidFarm(address _farm) private view returns (bool) {
        IFarm(_farm).getTokenAmounts();
        address[] memory rwdTokens = IFarm(_farm).getRewardTokens();
        uint256 rwdTokensLen = rwdTokens.length;
        for (uint8 i; i < rwdTokensLen;) {
            if (rwdTokens[i] == rewardToken) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice A function to validate the no lockup fund's reward percentage.
    /// @param _percentage No lockup fund's reward percentage to be validated.
    function _validateRewardPer(uint256 _percentage) private pure {
        if (_percentage == 0 || _percentage > MAX_PERCENTAGE) {
            revert InvalidRewardPercentage(_percentage);
        }
    }

    /// @notice Validate address.
    /// @param _addr Address to be validated.
    function _validateNonZeroAddr(address _addr) private pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
