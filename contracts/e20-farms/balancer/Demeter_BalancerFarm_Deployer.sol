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

import "../../BaseFarmDeployer.sol";
import "./interfaces/IBalancerVault.sol";
import {Demeter_BalancerFarm, RewardTokenData} from "./Demeter_BalancerFarm.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Deployer for Balancer farm
/// @author Sperax Foundation
/// @notice This contract allows anyone to calculate fees and create farms
/// @dev It consults Balancer's vault to validate the pool
contract Demeter_BalancerFarm_Deployer is BaseFarmDeployer, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // farmAdmin - Address to which ownership of farm is transferred to post deployment
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days)
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // poolId - ID of the pool, can be 2 to 8.
    //                  (tokenA, tokenB)
    // rewardTokenData - [(rewardTokenAddress, tknManagerAddress), ... ]
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        bytes32 poolId;
        RewardTokenData[] rewardData;
    }

    // All the pool actions happen on Balancer's vault
    address public immutable BALANCER_VAULT;
    string public DEPLOYER_NAME;

    // Custom Errors
    error InvalidTokens();

    /// @notice Constructor of the contract
    /// @param _factory Address of Sperax Farm Factory
    /// @param _balancerVault Address of Balancer's Vault
    /// @param _deployerName String containing a name of the deployer
    /// @dev Deploys one farm so that it can be cloned later
    constructor(address _factory, address _balancerVault, string memory _deployerName) BaseFarmDeployer(_factory) {
        _isNonZeroAddr(_balancerVault);

        BALANCER_VAULT = _balancerVault;
        DEPLOYER_NAME = _deployerName;
        discountedFee = 50e18; // 50 USDs
        farmImplementation = address(new Demeter_BalancerFarm());
    }

    /// @notice Deploys a new Balancer farm.
    /// @param _data data for deployment.
    /// @return Address of the new farm
    /// @dev The caller of this function should approve feeAmount (USDs) for this contract
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _isNonZeroAddr(_data.farmAdmin);

        address pairPool = validatePool(_data.poolId);
        (IERC20[] memory tokens,,) = IBalancerVault(BALANCER_VAULT).getPoolTokens(_data.poolId);

        // Calculate and collect fee if required
        _collectFee(tokens);

        Demeter_BalancerFarm farmInstance = Demeter_BalancerFarm(Clones.clone(farmImplementation));
        farmInstance.initialize(_data.farmStartTime, _data.cooldownPeriod, pairPool, _data.rewardData);
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice An external function to calculate fees when pool tokens are in array.
    /// @param _tokens Array of addresses of tokens
    /// @return feeReceiver's address, feeToken's address, feeAmount, boolean claimable
    function calculateFees(IERC20[] memory _tokens) external view returns (address, address, uint256, bool) {
        return _calculateFees(_tokens);
    }

    /// @notice A function to validate Balancer pool
    /// @param _poolId bytes32 Id of the pool
    function validatePool(bytes32 _poolId) public view returns (address pool) {
        (pool,) = IBalancerVault(BALANCER_VAULT).getPool(_poolId);
        _isNonZeroAddr(pool);
    }

    /// @notice An internal function to calculate fees when tokens are passed as an array
    /// @param _tokens Array of token addresses
    /// @return feeReceiver's address, feeToken's address, feeAmount, boolean claimable
    function _calculateFees(IERC20[] memory _tokens) internal view returns (address, address, uint256, bool) {
        uint8 tokensLen = uint8(_tokens.length);

        if (tokensLen == 0) {
            revert InvalidTokens();
        }

        (address feeReceiver, address feeToken, uint256 feeAmount) = IFarmFactory(factory).getFeeParams();
        if (IFarmFactory(factory).isPrivilegedDeployer(msg.sender)) {
            // No fees for privileged deployers
            feeAmount = 0;
            return (feeReceiver, feeToken, feeAmount, false);
        }
        for (uint8 i; i < tokensLen;) {
            if (_checkToken(address(_tokens[i]))) {
                // DiscountedFee if either of the token is SPA or USDs
                // This fees is claimable
                return (feeReceiver, feeToken, discountedFee, true);
            }
            unchecked {
                ++i;
            }
        }
        // No discount because neither of the token is SPA or USDs
        return (feeReceiver, feeToken, feeAmount, false);
    }

    /// @notice A function to collect the fees
    /// @param _tokens Array of token addresses
    function _collectFee(IERC20[] memory _tokens) private {
        (address feeReceiver, address feeToken, uint256 feeAmount, bool claimable) = _calculateFees(_tokens);
        if (feeAmount > 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
            emit FeeCollected(msg.sender, feeToken, feeAmount, claimable);
        }
    }
}
