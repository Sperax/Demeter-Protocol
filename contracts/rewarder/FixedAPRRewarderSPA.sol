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
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFarm} from "../interfaces/IFarm.sol";
import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {ICamelotFarm, IUniswapV3Farm, ILegacyFarm} from "./interfaces/ILegacyRewarderHelpers.sol";

/// @title FixedAPRRewarderSPA contract of Demeter Protocol
/// @notice This contract tracks farms, their APR, and rewards
/// @author Sperax Foundation
contract FixedAPRRewarderSPA is Ownable {
    using SafeERC20 for IERC20;

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // rewardRate - Amount of tokens emitted per second.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseTokens - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    // isUniV3Farm - True if the farm is Uniswap V3 type, false if CamelotV1 or UniswapV2
    struct FarmRewardConfig {
        uint256 apr;
        uint256 rewardRate;
        uint256 maxRewardRate;
        address[] baseTokens;
        uint256 noLockupRewardPer; // 5000 = 50%
        bool isUniV3Farm;
    }

    // Configuration for fixed APR reward tokens.
    // apr - APR of the reward stored in 8 precision.
    // maxRewardRate - Maximum amount of tokens to be emitted per second.
    // baseTokens - Addresses of tokens to be considered for calculating the L value.
    // nonLockupRewardPer - Reward percentage allocation for no lockup fund (rest goes to lockup fund).
    struct FarmRewardConfigParams {
        uint256 apr;
        uint256 maxRewardRate;
        address[] baseTokens;
        uint256 noLockupRewardPer; // 5000 = 50%
        bool isUniV3Farm;
    }

    uint8 public constant COMMON_FUND_ID = 0;
    uint256 public constant MAX_PERCENTAGE = 10000;
    uint256 public constant APR_PRECISION = 1e8;
    uint256 public constant REWARD_PERIOD = 1 weeks;
    address public constant REWARD_TOKEN = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant UNISWAP_UTILS = 0xd2Aa19D3B7f8cdb1ea5B782c5647542055af415e;
    string public constant CAMELOT_FARM_ID = "Demeter_Camelot_v1";
    address public oracle;
    uint256 public totalRewardRate;

    // farm -> FarmRewardConfig
    mapping(address => FarmRewardConfig) public farmRewardConfigs;
    mapping(address => uint8) private _decimals;

    event OracleUpdated(address newOracle);
    event RewardConfigUpdated(address indexed farm, FarmRewardConfigParams rewardConfig);
    event RewardsCalibrated(address indexed farm, uint256 rewardsSent, uint256 rewardRate);

    error FarmNotSupported();
    error InvalidAddress();
    error InvalidFarm();
    error ZeroAmount();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);

    /// @notice Constructor of this contract.
    /// @param _oracle Address of the USDs Master Price Oracle.
    /// @param _admin Admin/ deployer of this contract.
    constructor(address _oracle, address _admin) {
        updateOracle(_oracle);
        _validateNonZeroAddr(_admin);
        _transferOwnership(_admin);
    }

    /// @notice A function to update the rewardToken configuration.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, FarmRewardConfigParams memory _rewardConfig) external onlyOwner {
        // validating new reward config
        uint256 baseTokensLen = _rewardConfig.baseTokens.length;
        for (uint256 i; i < baseTokensLen;) {
            _validatePriceFeed(_rewardConfig.baseTokens[i]);
            unchecked {
                ++i;
            }
        }
        _validateRewardPer(_rewardConfig.noLockupRewardPer);
        farmRewardConfigs[_farm] = FarmRewardConfig({
            apr: _rewardConfig.apr,
            rewardRate: farmRewardConfigs[_farm].rewardRate,
            maxRewardRate: _rewardConfig.maxRewardRate,
            baseTokens: _rewardConfig.baseTokens,
            noLockupRewardPer: _rewardConfig.noLockupRewardPer,
            isUniV3Farm: _rewardConfig.isUniV3Farm
        });
        emit RewardConfigUpdated(_farm, _rewardConfig);
        calibrateRewards(_farm);
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

    /// @notice A function to calculate the time till which rewards are there for an LP.
    /// @param _farm Address of the farm for which the end time is to be calculated.
    /// @return rewardsEndingOn Timestamp in seconds till which the rewards are there in farm and in rewarder.
    function rewardsEndTime(address _farm) external view returns (uint256 rewardsEndingOn) {
        uint256 farmBalance = IERC20(REWARD_TOKEN).balanceOf(_farm);
        uint256 rewarderBalance = IERC20(REWARD_TOKEN).balanceOf(address(this));
        rewardsEndingOn = block.timestamp
            + ((farmBalance / farmRewardConfigs[_farm].rewardRate) + (rewarderBalance / totalRewardRate));
    }

    /// @notice A function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateRewards(address _farm) public returns (uint256 rewardsToSend) {
        FarmRewardConfig memory farmRewardConfig = farmRewardConfigs[_farm];
        if (farmRewardConfig.apr != 0) {
            (address[] memory assets, uint256[] memory amounts) = getTokenAmounts(_farm);
            uint256 assetsLen = assets.length;
            // Calculating total USD value for all the assets.
            uint256 totalValue;
            uint256 baseTokensLen = farmRewardConfig.baseTokens.length;
            IOracle.PriceData memory _priceData;
            for (uint8 iFarmTokens; iFarmTokens < assetsLen;) {
                for (uint8 jBaseTokens; jBaseTokens < baseTokensLen;) {
                    if (assets[iFarmTokens] == farmRewardConfig.baseTokens[jBaseTokens]) {
                        _priceData = _getPrice(assets[iFarmTokens]);
                        totalValue += (_priceData.price * _normalizeAmount(assets[iFarmTokens], amounts[iFarmTokens]))
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
            _priceData = _getPrice(REWARD_TOKEN);
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
            emit RewardsCalibrated(_farm, rewardsToSend, rewardRate);
        } else {
            _setRewardRate(_farm, 0, farmRewardConfig.noLockupRewardPer);
            _adjustGlobalRewardRate(farmRewardConfig.rewardRate, 0);
            farmRewardConfigs[_farm].rewardRate = 0;
            emit RewardsCalibrated(_farm, 0, 0);
        }
    }

    /// @notice A function to update Oracle.
    /// @param _newOracle Address of the new oracle.
    /// @dev It checks whether oracle has valid price feed for REWARD_TOKEN.
    function updateOracle(address _newOracle) public onlyOwner {
        oracle = _newOracle;
        _validatePriceFeed(REWARD_TOKEN);
        emit OracleUpdated(_newOracle);
    }

    /// @notice A function to get token amounts.
    /// @param _farm Address of the farm.
    function getTokenAmounts(address _farm) public view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 totalLiquidity = IFarm(_farm).getRewardFundInfo(COMMON_FUND_ID).totalLiquidity;
        if (farmRewardConfigs[_farm].isUniV3Farm) {
            return TokenUtils.getUniV3TokenAmounts(
                IUniswapV3Farm(_farm).uniswapPool(),
                UNISWAP_UTILS,
                IUniswapV3Farm(_farm).tickLowerAllowed(),
                IUniswapV3Farm(_farm).tickUpperAllowed(),
                totalLiquidity
            );
        } else {
            return TokenUtils.getUniV2TokenAmounts(ICamelotFarm(_farm).nftPool(), totalLiquidity);
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

    /// @notice A function to fetch and get the price of a token.
    /// @param _token Token for which the the price is to be fetched.
    function _getPrice(address _token) private view returns (IOracle.PriceData memory _priceData) {
        _priceData = IOracle(oracle).getPrice(_token);
    }

    /// @notice A function to validate price feed.
    /// @param _token Token to be validated.
    function _validatePriceFeed(address _token) private view {
        if (!IOracle(oracle).priceFeedExists(_token)) {
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

    /// @notice Validate address.
    /// @param _addr Address to be validated.
    function _validateNonZeroAddr(address _addr) private pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
