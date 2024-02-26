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

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFarm} from "../interfaces/IFarm.sol";
import {IFarmRegistry} from "../interfaces/IFarmRegistry.sol";

/// @title Rewarder contract of Demeter Protocol
/// @notice This contract tracks farms, their APR, and rewards
/// @author Sperax Foundation
contract DemeterRewarder is Initializable, OwnableUpgradeable {
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
    address public oracle;
    address public farmRegistry;
    // farm -> token -> FixedAPRRewardConfig
    mapping(address => mapping(address => FixedAPRRewardConfig)) public rewardTokens;
    // token -> manager
    mapping(address => address) public tokenToManager;
    // token -> rewards per second for all the farms
    mapping(address => uint256) public tokenToRewardsPerSec;

    event OracleUpdated(address newOracle);
    event FarmRegistryUpdated(address newFarmRegistry);
    event TokenManagerUpdated(address token, address newManager);
    event RewardConfigUpdated(address indexed farm, address indexed token, FixedAPRRewardConfig rewardConfig);
    event RewardTokenCalibrated(
        address indexed farm, address indexed token, uint256 rewardsSent, uint256 rewardsPerSecond
    );

    error InvalidAddress();
    error NotTheTokenManager();
    error UnrecognizedFarm();
    error PriceFeedDoesNotExist(address token);
    error InvalidRewardPercentage(uint256 percentage);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function of this contract.
    /// @param _oracle Address of the oracle contract.
    function initialize(address _oracle, address _farmRegistry) external initializer {
        __Ownable_init();
        updateOracle(_oracle);
        updateFarmRegistry(_farmRegistry);
    }

    /// @notice A function to update the rewardToken configuration.
    /// @param _farm Address of the farm for which the config is to be updated.
    /// @param _token Reward token for which the config is to be updated.
    /// @param _rewardConfig The config which is to be set.
    function updateRewardConfig(address _farm, address _token, FixedAPRRewardConfig memory _rewardConfig) external {
        _validateTokenManager(_token);
        _validateFarm(_farm);
        address _oracle = oracle;
        // validating new reward config
        uint256 baseTokensLen = _rewardConfig.baseTokens.length;
        for (uint256 i; i < baseTokensLen;) {
            if (!IOracle(_oracle).priceFeedExists(_rewardConfig.baseTokens[i])) {
                revert PriceFeedDoesNotExist(_rewardConfig.baseTokens[i]);
            }
            unchecked {
                ++i;
            }
        }
        _validateRewardPer(_rewardConfig.noLockupRewardPer);
        _rewardConfig.rewardsPerSec = 0;
        rewardTokens[_farm][_token] = _rewardConfig;
        emit RewardConfigUpdated(_farm, _token, _rewardConfig);
    }

    /// @notice A function to calibrate rewards for a reward token for a farm.
    /// @param _farm Address of the farm for which the rewards are to be calibrated.
    /// @param _rewardToken Address of the reward token for which the rewards are to be calibrated.
    /// @return rewardsToSend Rewards which are sent to the farm.
    /// @dev Calculates based on APR, caps based on maxRewardPerSec or balance rewards.
    function calibrateRewards(address _farm, address _rewardToken) external returns (uint256 rewardsToSend) {
        _validateFarm(_farm);
        FixedAPRRewardConfig memory rewardToken = rewardTokens[_farm][_rewardToken];
        if (rewardToken.apr != 0 && IFarm(_farm).isFarmActive()) {
            (address[] memory _assets, uint256[] memory _amounts) = IFarm(_farm).getTokenAmounts();
            uint256 _assetsLen = _assets.length;
            if (_assetsLen == _amounts.length) {
                uint256 totalValue;
                uint256 baseTokensLen = rewardToken.baseTokens.length;
                for (uint8 iFarmTokens; iFarmTokens < _assetsLen;) {
                    for (uint8 jBaseTokens; jBaseTokens < baseTokensLen;) {
                        if (_assets[iFarmTokens] == rewardToken.baseTokens[jBaseTokens]) {
                            IOracle.PriceData memory _priceData = IOracle(oracle).getPrice(_assets[iFarmTokens]);
                            totalValue += (
                                _priceData.price * _normalizeAmount(_assets[iFarmTokens], _amounts[iFarmTokens])
                            ) / _priceData.precision;
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
                IOracle.PriceData memory _rwdPriceData = IOracle(oracle).getPrice(_rewardToken);
                uint256 rewardsPerSecond = (
                    (((rewardToken.apr * totalValue) / (APR_PRECISION * 100)) / 365 days) * _rwdPriceData.precision
                ) / _rwdPriceData.price;
                if (rewardsPerSecond > rewardToken.maxRewardsPerSec) {
                    rewardsPerSecond = rewardToken.maxRewardsPerSec;
                }
                uint256 _farmRwdBalance = IERC20(_rewardToken).balanceOf(_farm);
                uint256 _rewarderRwdBalance = IERC20(_rewardToken).balanceOf(address(this));
                rewardsToSend = (rewardsPerSecond * 1 weeks);
                if (rewardsToSend > _farmRwdBalance) {
                    rewardsToSend -= _farmRwdBalance;
                    if (rewardsToSend > _rewarderRwdBalance) {
                        rewardsToSend = _rewarderRwdBalance;
                        rewardsPerSecond = (_farmRwdBalance + _rewarderRwdBalance) / 1 weeks;
                    }
                    IERC20(_rewardToken).safeTransfer(_farm, rewardsToSend);
                } else {
                    rewardsToSend = 0;
                }
                _setRewardRate(_farm, _rewardToken, rewardsPerSecond, rewardToken.noLockupRewardPer);
                _adjustGlobalRewardsPerSec(_rewardToken, rewardToken.rewardsPerSec, rewardsPerSecond);
                rewardTokens[_farm][_rewardToken].rewardsPerSec = rewardsPerSecond;
                emit RewardTokenCalibrated(_farm, _rewardToken, rewardsToSend, rewardsPerSecond);
            }
        }
    }

    /// @notice A function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _token Token for which the manager has to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerInFarm(address _farm, address _token, address _newManager) external {
        _validateTokenManager(_token);
        _validateFarm(_farm);
        IFarm(_farm).updateRewardData(_token, _newManager);
    }

    /// @notice A function to update the token manager in this contract.
    /// @param _token Address of the token of which the manager is to be updated.
    /// @param _newManager Address of the desired manager.
    function updateTokenManager(address _token, address _newManager) external onlyOwner {
        _validateNonZeroAddr(_token);
        _validateNonZeroAddr(_newManager);
        tokenToManager[_token] = _newManager;
        emit TokenManagerUpdated(_token, _newManager);
    }

    /// @notice A function to update the oracle address.
    /// @param _newOracle Address of the desired oracle to be set.
    function updateOracle(address _newOracle) public onlyOwner {
        _validateNonZeroAddr(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice A function to update the farm registry address.
    /// @param _newFarmRegistry Address of the desired farm registry to be set.
    function updateFarmRegistry(address _newFarmRegistry) public onlyOwner {
        _validateNonZeroAddr(_newFarmRegistry);
        farmRegistry = _newFarmRegistry;
        emit FarmRegistryUpdated(_newFarmRegistry);
    }

    /// @notice A function to set reward rate in the farm.
    /// @param _farm Address of the farm.
    /// @param _rwdToken Address of the reward token.
    /// @param _rwdPerSec Reward per second to be emitted.
    /// @param _noLockupRewardPer Reward percentage to be allocated to no lockup fund
    function _setRewardRate(address _farm, address _rwdToken, uint256 _rwdPerSec, uint256 _noLockupRewardPer) private {
        uint256[] memory _newRewardRates;
        if (IFarm(_farm).cooldownPeriod() == 0) {
            _newRewardRates = new uint256[](1);
            _newRewardRates[0] = _rwdPerSec;
            IFarm(_farm).setRewardRate(_rwdToken, _newRewardRates);
        } else {
            _newRewardRates = new uint256[](2);
            uint256 commonFundShare = (_rwdPerSec * _noLockupRewardPer) / MAX_PERCENTAGE;
            _newRewardRates[0] = commonFundShare;
            _newRewardRates[1] = _rwdPerSec - commonFundShare;
            IFarm(_farm).setRewardRate(_rwdToken, _newRewardRates);
        }
    }

    /// @notice A function to adjust global rewards per second emitted for a reward token.
    /// @param _rewardToken Reward token for which the global emissions are to be updated.
    /// @param _oldRewardsPerSec Old emission rate.
    /// @param _newRewardsPerSecond New emission rate.
    function _adjustGlobalRewardsPerSec(address _rewardToken, uint256 _oldRewardsPerSec, uint256 _newRewardsPerSecond)
        private
    {
        tokenToRewardsPerSec[_rewardToken] -= _oldRewardsPerSec;
        tokenToRewardsPerSec[_rewardToken] += _newRewardsPerSecond;
    }

    /// @notice A function to validate token manager of the farm's reward token.
    ///         A valid token manager should be the token manager of the reward _token in the _farm
    ///         or it should be the token manager in this contracts rewardTokens.
    /// @param _token Address of the token for which the token manager will be checked.
    function _validateTokenManager(address _token) private view {
        if (tokenToManager[_token] != msg.sender) {
            revert NotTheTokenManager();
        }
    }

    /// @notice A function to normalize asset amounts to be of precision 1e18.
    /// @param _token Address of the asset token.
    /// @param _amount Amount of the token.
    /// @return Normalized amount of the token in 1e18.
    function _normalizeAmount(address _token, uint256 _amount) private view returns (uint256) {
        uint8 _decimals = ERC20(_token).decimals();
        if (_decimals != 18) {
            _amount *= 10 ** (18 - _decimals);
        }
        return _amount;
    }

    /// @notice A function to validate farm.
    /// @param _farm Address of the farm to be validated.
    /// @dev It checks Demeter Farm registry for a valid, registered farm.
    function _validateFarm(address _farm) private view {
        if (!IFarmRegistry(farmRegistry).farmRegistered(_farm)) {
            revert UnrecognizedFarm();
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
