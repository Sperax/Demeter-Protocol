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

import {FarmDeployer, SafeERC20, IERC20, IFarmRegistry} from "../../FarmDeployer.sol";
import {IBalancerV2Vault} from "./interfaces/IBalancerV2Vault.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RewardTokenData} from "../E20Farm.sol";
import {BalancerV2Farm} from "./BalancerV2Farm.sol";

/// @title Deployer for Balancer V2 farm.
/// @author Sperax Foundation.
/// @notice This contract allows anyone to calculate fees, pay fees and create farms.
/// @dev It consults Balancer V2 Vault to validate the pool.
contract BalancerV2FarmDeployer is FarmDeployer {
    using SafeERC20 for IERC20;

    // farmAdmin - Address to which ownership of farm is transferred to, post deployment.
    // farmStartTime - Timestamp when reward accrual begins for deposits in the farm.
    // cooldownPeriod -  Cooldown period for locked deposits (in days).
    //                   Make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // poolId - ID of the pool. It is used to fetch the pool data from Balancer's vault.
    // rewardTokenData - An array containing pairs of reward token addresses and their corresponding token manager addresses.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        bytes32 poolId;
        RewardTokenData[] rewardData;
    }

    // All the pool actions happen on Balancer's vault.
    address public immutable BALANCER_VAULT;

    /// @notice Constructor.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    /// @param _balancerVault Address of Balancer's Vault.
    /// @dev Deploys one farm so that it can be cloned later.
    constructor(address _farmRegistry, string memory _farmId, address _balancerVault)
        FarmDeployer(_farmRegistry, _farmId)
    {
        _validateNonZeroAddr(_balancerVault);

        BALANCER_VAULT = _balancerVault;
        farmImplementation = address(new BalancerV2Farm());
    }

    /// @notice Deploys a new Balancer farm.
    /// @param _data Data for deployment.
    /// @return Address of the deployed farm.
    /// @dev The caller of this function should approve feeAmount to this contract before calling this function.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);

        address pairPool = validatePool(_data.poolId);

        // Calculate and collect fee if required.
        _collectFee();

        BalancerV2Farm farmInstance = BalancerV2Farm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _farmRegistry: FARM_REGISTRY,
            _farmToken: pairPool,
            _rwdTokenData: _data.rewardData
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice Function to validate Balancer pool.
    /// @param _poolId bytes32 Id of the pool.
    /// @return pool Pool address.
    function validatePool(bytes32 _poolId) public view returns (address pool) {
        (pool,) = IBalancerV2Vault(BALANCER_VAULT).getPool(_poolId);
        _validateNonZeroAddr(pool);
    }
}
