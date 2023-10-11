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

import {BaseFarmDeployer, IFarmFactory} from "../BaseFarmDeployer.sol";
import {Demeter_UniV3Farm, RewardTokenData, UniswapPoolData} from "./Demeter_UniV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Demeter_UniV3FarmDeployer
/// @notice This contract deploys UniswapV3 farms with configurable parameters.
/// @dev It inherits from BaseFarmDeployer and uses the Clones library to create farm instances.
/// @dev Farms created by this contract are managed by the Demeter_UniV3Farm contract.
/// @author Sperax Foundation
contract Demeter_UniV3FarmDeployer is BaseFarmDeployer, ReentrancyGuard {
    /// @dev Struct to hold data required for farm deployment.
    /// @param farmAdmin The address to which ownership of the farm is transferred to post-deployment.
    /// @param farmStartTime Time after which the rewards start accruing for the deposits in the farm.
    /// @param cooldownPeriod Cooldown period for locked deposits (in days).
    ///        Make cooldownPeriod = 0 for disabling the lockup functionality of the farm.
    /// @param uniswapPoolData Initialization data for UniswapV3 pool.
    ///        (tokenA, tokenB, feeTier, tickLower, tickUpper)
    /// @param rewardData Array of tuples containing reward token address and token manager address.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        UniswapPoolData uniswapPoolData;
        RewardTokenData[] rewardData;
    }

    /// @dev Name of this deployer contract.
    string public constant DEPLOYER_NAME = "Demeter_UniV3FarmDeployer_v3";

    /// @dev Constructs the Demeter_UniV3FarmDeployer contract.
    /// @param _factory Address of the factory contract used for farm registration.
    constructor(address _factory) BaseFarmDeployer(_factory) {
        discountedFee = 50e18; // 50 USDs
        farmImplementation = address(new Demeter_UniV3Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data Data for deployment.
    /// @return The address of the newly created farm.
    function createFarm(FarmData memory _data)
        external
        nonReentrant
        returns (address)
    {
        _isNonZeroAddr(_data.farmAdmin);
        Demeter_UniV3Farm farmInstance = Demeter_UniV3Farm(
            Clones.clone(farmImplementation)
        );
        farmInstance.initialize(
            _data.farmStartTime,
            _data.cooldownPeriod,
            _data.uniswapPoolData,
            _data.rewardData
        );
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee(_data.uniswapPoolData.tokenA, _data.uniswapPoolData.tokenB);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        return farm;
    }
}
