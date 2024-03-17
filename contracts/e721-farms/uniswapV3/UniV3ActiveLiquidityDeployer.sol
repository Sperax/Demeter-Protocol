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

import {FarmDeployer, IFarmRegistry} from "../../FarmDeployer.sol";
import {RewardTokenData, UniswapPoolData} from "./UniV3Farm.sol";
import {UniV3ActiveLiquidityFarm} from "./UniV3ActiveLiquidityFarm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract UniV3ActiveLiquidityDeployer is FarmDeployer, ReentrancyGuard {
    // farmAdmin - Address to which ownership of farm is transferred to post deployment
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days)
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // uniswapPoolData - Init data for UniswapV3 pool.
    //                  (tokenA, tokenB, feeTier, tickLower, tickUpper)
    // rewardTokenData - [(rewardTokenAddress, tknManagerAddress), ... ]
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        UniswapPoolData uniswapPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable UNI_V3_FACTORY; // Uniswap V3 factory
    address public immutable NFPM; // Uniswap NonfungiblePositionManager contract

    /// @notice Constructor of the contract
    /// @param _farmRegistry Address of the Demeter Farm Registry
    /// @param _farmId Id of the farm
    /// @param _uniV3Factory Address of UniswapV3 factory
    /// @param _nfpm Address of Uniswap NonfungiblePositionManager contract
    constructor(address _farmRegistry, string memory _farmId, address _uniV3Factory, address _nfpm)
        FarmDeployer(_farmRegistry, _farmId)
    {
        _validateNonZeroAddr(_uniV3Factory);
        _validateNonZeroAddr(_nfpm);

        UNI_V3_FACTORY = _uniV3Factory;
        NFPM = _nfpm;
        farmImplementation = address(new UniV3ActiveLiquidityFarm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);

        UniV3ActiveLiquidityFarm farmInstance = UniV3ActiveLiquidityFarm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _farmRegistry: FARM_REGISTRY,
            _uniswapPoolData: _data.uniswapPoolData,
            _rwdTokenData: _data.rewardData,
            _uniV3Factory: UNI_V3_FACTORY,
            _nftContract: NFPM
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        return farm;
    }
}
