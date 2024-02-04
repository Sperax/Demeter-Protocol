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

import {BaseFarmDeployer, SafeERC20, IERC20, IFarmFactory} from "../../BaseFarmDeployer.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BaseE20Farm, RewardTokenData} from "../BaseE20Farm.sol";

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

    /// @notice Constructor of the contract
    /// @param _factory Address of Sperax Farm Factory
    /// @param _farmId Id of the farm
    /// @param _balancerVault Address of Balancer's Vault
    /// @dev Deploys one farm so that it can be cloned later
    constructor(address _factory, string memory _farmId, address _balancerVault) BaseFarmDeployer(_factory, _farmId) {
        _ensureItsNonZeroAddr(_balancerVault);

        BALANCER_VAULT = _balancerVault;
        farmImplementation = address(new BaseE20Farm());
    }

    /// @notice Deploys a new Balancer farm.
    /// @param _data data for deployment.
    /// @return Address of the new farm
    /// @dev The caller of this function should approve feeAmount (USDs) for this contract
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _ensureItsNonZeroAddr(_data.farmAdmin);

        address pairPool = validatePool(_data.poolId);

        // Calculate and collect fee if required
        _collectFee();

        BaseE20Farm farmInstance = BaseE20Farm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _factory: FACTORY,
            _farmToken: pairPool,
            _rwdTokenData: _data.rewardData
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        IFarmFactory(FACTORY).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice A function to validate Balancer pool
    /// @param _poolId bytes32 Id of the pool
    function validatePool(bytes32 _poolId) public view returns (address pool) {
        (pool,) = IBalancerVault(BALANCER_VAULT).getPool(_poolId);
        _ensureItsNonZeroAddr(pool);
    }
}
