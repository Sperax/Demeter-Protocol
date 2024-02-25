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

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FixedAPRRewardConfig, RewardData} from "../interfaces/DataTypes.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFarmFactory} from "../interfaces/IFarmFactory.sol";

interface IFarm {
    function updateRewardData(address _rwdToken, address _newTknManager) external;
    function setRewardRate(address _rwdToken, uint256[] memory _newRwdRates) external;
    function rewardData(address _token) external view returns (RewardData memory);
    function getTokenAmounts() external view returns (address[] memory, uint256[] memory);
    function cooldownPeriod() external view returns (uint256);
}

/// @title Rewarder contract of Demeter Protocol
/// @notice This contract tracks farms, their APR, and rewards
/// @author Sperax Foundation
contract DemeterRewarder is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_PERCENTAGE = 10000;
    uint256 public constant APR_PRECISION = 1e8;
    address public oracle;
    address public farmRegistry;
    // farm -> token -> FixedAPRRewardConfig
    mapping(address => mapping(address => FixedAPRRewardConfig)) public rewardTokens;

    event OracleUpdated(address newOracle);
    event FarmRegistryUpdated(address newFarmRegistry);
    event RewardConfigUpdated(address indexed farm, address indexed token, FixedAPRRewardConfig rewardConfig);

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
        _validateTokenManager(_farm, _token);
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
        _validateNonZeroAddr(_rewardConfig.tokenManager);
        _validateRewardPer(_rewardConfig.noLockupRewardPer);
        rewardTokens[_farm][_token] = _rewardConfig;
        emit RewardConfigUpdated(_farm, _token, _rewardConfig);
    }

    // @todo work on this function
    function calibrateRewards(address _farm, address _rewardToken) external returns (uint256 rewardsToSend) {
        _validateFarm(_farm);
        FixedAPRRewardConfig memory rewardToken = rewardTokens[_farm][_rewardToken];
        if (rewardToken.apr != 0) {
            (address[] memory _assets, uint256[] memory _amounts) = IFarm(_farm).getTokenAmounts();
            uint256 _assetsLen = _assets.length;
            if (_assetsLen == _amounts.length) {
                uint256 totalValue;
                uint256 baseTokensLen = rewardToken.baseTokens.length;
                for (uint8 iFarmTokens; iFarmTokens < _assetsLen;) {
                    for (uint8 jBaseTokens; jBaseTokens < baseTokensLen;) {
                        if (_assets[iFarmTokens] == rewardToken.baseTokens[jBaseTokens]) {
                            IOracle.PriceData memory _priceData = IOracle(oracle).getPrice(_assets[iFarmTokens]);
                            uint256 _normalizedAmount = _normalizeAmount(_assets[iFarmTokens], _amounts[iFarmTokens]);
                            totalValue += _priceData.price * _normalizedAmount / _priceData.precision;
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
                uint256 rewardValuePerSecond = ((rewardToken.apr * totalValue) / (APR_PRECISION * 100)) / 365 days;
                IOracle.PriceData memory _rwdPriceData = IOracle(oracle).getPrice(_rewardToken);
                uint256 rewardsPerSecond = (rewardValuePerSecond * _rwdPriceData.precision) / _rwdPriceData.price;
                if (rewardsPerSecond > rewardToken.maxRewardsPerSec) {
                    rewardsPerSecond = rewardToken.maxRewardsPerSec;
                }
                _setRewardRate(_farm, _rewardToken, rewardsPerSecond, rewardToken.noLockupRewardPer);
                // Sending rewards to the farm.
                rewardsToSend = (rewardsPerSecond * 1 weeks) - IERC20(_rewardToken).balanceOf(_farm);
                uint256 _rewarderBalance = IERC20(_rewardToken).balanceOf(_farm);
                if (rewardsToSend > _rewarderBalance) {
                    rewardsToSend = _rewarderBalance;
                }
                if (rewardsToSend != 0) {
                    IERC20(_rewardToken).safeTransfer(_farm, rewardsToSend);
                }
            }
        }
    }

    /// @notice A function to update the token manager's address in the farm.
    /// @param _farm Farm's address in which the token manager is to be updated.
    /// @param _token Token for which the manager has to be updated.
    /// @param _newManager Address of the new token manager.
    function updateTokenManagerInFarm(address _farm, address _token, address _newManager) external {
        if (msg.sender != rewardTokens[_farm][_token].tokenManager) {
            revert NotTheTokenManager();
        }
        IFarm(_farm).updateRewardData(_token, _newManager);
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
            uint256 lockupFundShare = _rwdPerSec - commonFundShare;
            _newRewardRates[1] = lockupFundShare;
            IFarm(_farm).setRewardRate(_rwdToken, _newRewardRates);
        }
    }

    /// @notice A function to validate token manager of the farm's reward token.
    ///         A valid token manager should be the token manager of the reward _token in the _farm
    ///         or it should be the token manager in this contracts rewardTokens.
    /// @param _farm Address of the farm in which the token manager will be checked.
    /// @param _token Address of the token for which the token manager will be checked.
    function _validateTokenManager(address _farm, address _token) private view {
        if (
            IFarm(_farm).rewardData(_token).tknManager != msg.sender
                && rewardTokens[_farm][_token].tokenManager != msg.sender
        ) {
            revert NotTheTokenManager();
        }
    }

    function _normalizeAmount(address _token, uint256 _amount) private view returns (uint256) {
        uint8 _decimals = ERC20(_token).decimals();
        if (_decimals != 18) {
            _amount *= 10 ** (18 - _decimals);
        }
        return _amount;
    }

    function _validateFarm(address _farm) private view {
        if (!IFarmFactory(farmRegistry).farmRegistered(_farm)) {
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
