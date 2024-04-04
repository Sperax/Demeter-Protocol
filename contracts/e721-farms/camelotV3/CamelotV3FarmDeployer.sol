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

import {FarmDeployer, IFarmRegistry} from "../../FarmDeployer.sol";
import {CamelotV3Farm, RewardTokenData, CamelotPoolData, InitializeInput} from "./CamelotV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title Deployer for Camelot V3 farm.
/// @author Sperax Foundation.
/// @notice This contract allows anyone to calculate fees, pay fees and create farms.
contract CamelotV3FarmDeployer is FarmDeployer {
    // farmAdmin - Address to which ownership of farm is transferred to, post deployment.
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days).
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // camelotPoolData - Init data for CamelotV3 pool (tokenA, tokenB, tickLower, tickUpper).
    // rewardTokenData - An array containing pairs of reward token addresses and their corresponding token manager addresses.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        CamelotPoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable CAMELOT_V3_FACTORY; // Camelot V3 factory.
    address public immutable NFPM; // Camelot NonfungiblePositionManager contract.
    address public immutable CAMELOT_UTILS; // CamelotUtils (Camelot helper) contract.
    address public immutable CAMELOT_NFPM_UTILS; // Camelot INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract.

    /// @notice Constructor of the contract.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    /// @param _camelotV3Factory Address of CamelotV3 factory.
    /// @param _nfpm Address of Camelot NonfungiblePositionManager contract.
    /// @param _camelotUtils Address of CamelotUtils (Camelot helper) contract.
    /// @param _nfpmUtils Address of Camelot INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract.
    constructor(
        address _farmRegistry,
        string memory _farmId,
        address _camelotV3Factory,
        address _nfpm,
        address _camelotUtils,
        address _nfpmUtils
    ) FarmDeployer(_farmRegistry, _farmId) {
        _validateNonZeroAddr(_camelotV3Factory);
        _validateNonZeroAddr(_nfpm);
        _validateNonZeroAddr(_camelotUtils);
        _validateNonZeroAddr(_nfpmUtils);

        CAMELOT_V3_FACTORY = _camelotV3Factory;
        NFPM = _nfpm;
        CAMELOT_UTILS = _camelotUtils;
        CAMELOT_NFPM_UTILS = _nfpmUtils;
        farmImplementation = address(new CamelotV3Farm());
    }

    /// @notice Deploys a new CamelotV3 farm.
    /// @param _data data for deployment.
    /// @return address of the deployed farm.
    /// @dev The caller of this function should approve feeAmount to this contract before calling this function.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);

        CamelotV3Farm farmInstance = CamelotV3Farm(Clones.clone(farmImplementation));
        InitializeInput memory input = InitializeInput({
            farmId: farmId,
            farmStartTime: _data.farmStartTime,
            cooldownPeriod: _data.cooldownPeriod,
            farmRegistry: FARM_REGISTRY,
            camelotPoolData: _data.camelotPoolData,
            rwdTokenData: _data.rewardData,
            camelotV3Factory: CAMELOT_V3_FACTORY,
            nftContract: NFPM,
            camelotUtils: CAMELOT_UTILS,
            nfpmUtils: CAMELOT_NFPM_UTILS
        });
        farmInstance.initialize({_input: input});
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required.
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        return farm;
    }
}
