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
import {UniV3Farm, RewardTokenData, UniswapPoolData, InitializeInput} from "./UniV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title Deployer for Uniswap V3 farm.
/// @author Sperax Foundation.
/// @notice This contract allows anyone to calculate fees, pay fees and create farms.
contract UniV3FarmDeployer is FarmDeployer {
    // farmAdmin - Address to which ownership of farm is transferred to, post deployment.
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  Cooldown period for locked deposits (in days).
    //                   Make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // uniswapPoolData - Init data for UniswapV3 pool (tokenA, tokenB, feeTier, tickLower, tickUpper).
    // rewardTokenData - An array containing pairs of reward token addresses and their corresponding token manager addresses.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        UniswapPoolData uniswapPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable UNI_V3_FACTORY; // Uniswap V3 factory.
    address public immutable NFPM; // Uniswap NonfungiblePositionManager contract.
    address public immutable UNISWAP_UTILS; // UniswapUtils (Uniswap helper) contract.
    address public immutable NFPM_UTILS; // Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract.

    /// @notice Constructor of the contract.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    /// @param _uniV3Factory Address of UniswapV3 factory.
    /// @param _nfpm Address of Uniswap NonfungiblePositionManager contract.
    /// @param _uniswapUtils Address of UniswapUtils (Uniswap helper) contract.
    /// @param _nfpmUtils Address of Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract.
    constructor(
        address _farmRegistry,
        string memory _farmId,
        address _uniV3Factory,
        address _nfpm,
        address _uniswapUtils,
        address _nfpmUtils
    ) FarmDeployer(_farmRegistry, _farmId) {
        _validateNonZeroAddr(_uniV3Factory);
        _validateNonZeroAddr(_nfpm);
        _validateNonZeroAddr(_uniswapUtils);
        _validateNonZeroAddr(_nfpmUtils);

        UNI_V3_FACTORY = _uniV3Factory;
        NFPM = _nfpm;
        UNISWAP_UTILS = _uniswapUtils;
        NFPM_UTILS = _nfpmUtils;
        farmImplementation = address(new UniV3Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data Data for deployment.
    /// @return Address of the deployed farm.
    /// @dev The caller of this function should approve feeAmount to this contract before calling this function.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);

        UniV3Farm farmInstance = UniV3Farm(Clones.clone(farmImplementation));
        farmInstance.initialize(
            InitializeInput({
                farmId: farmId,
                farmStartTime: _data.farmStartTime,
                cooldownPeriod: _data.cooldownPeriod,
                farmRegistry: FARM_REGISTRY,
                uniswapPoolData: _data.uniswapPoolData,
                rwdTokenData: _data.rewardData,
                uniV3Factory: UNI_V3_FACTORY,
                nftContract: NFPM,
                uniswapUtils: UNISWAP_UTILS,
                nfpmUtils: NFPM_UTILS
            })
        );
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required.
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        return farm;
    }
}
