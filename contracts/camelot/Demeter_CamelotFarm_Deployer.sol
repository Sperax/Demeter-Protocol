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
import {Demeter_CamelotFarm, RewardTokenData} from "./Demeter_CamelotFarm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ICamelotFactory} from "./interfaces/CamelotInterfaces.sol";

/// @title Demeter_CamelotFarm_Deployer
/// @notice This contract deploys Camelot farms with configurable parameters.
/// @dev It inherits from BaseFarmDeployer and uses the Clones library to create farm instances.
/// @dev Farms created by this contract are managed by the Demeter_CamelotFarm contract.
contract Demeter_CamelotFarm_Deployer is BaseFarmDeployer, ReentrancyGuard {
    /// @dev Struct to hold data required for Camelot pool configuration.
    /// @param tokenA Address of token A in the Camelot pool.
    /// @param tokenB Address of token B in the Camelot pool.
    struct CamelotPoolData {
        address tokenA;
        address tokenB;
    }

    /// @dev Struct to hold data required for farm deployment.
    /// @param farmAdmin Address to which ownership of the farm is transferred post deployment.
    /// @param farmStartTime Time when rewards start accruing for deposits in the farm.
    /// @param cooldownPeriod Cooldown period for locked deposits (in days).
    ///     Set to 0 to disable the lockup functionality of the farm.
    /// @param camelotPoolData Data for the Camelot pool (tokenA, tokenB).
    /// @param rewardData Array of tuples containing reward token address and token manager address.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        CamelotPoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    /// @notice Name of this deployer contract.
    string public constant DEPLOYER_NAME = "Demeter_CamelotFarmDeployer_v1";

    /// @notice Address of the protocol factory contract.
    address public immutable PROTOCOL_FACTORY;

    /// @dev Constructs the Demeter_CamelotFarm_Deployer contract.
    /// @param _factory Address of the factory contract used for farm registration.
    /// @param _protocolFactory Address of the Camelot protocol factory contract.
    constructor(address _factory, address _protocolFactory)
        BaseFarmDeployer(_factory)
    {
        _isNonZeroAddr(_protocolFactory);
        PROTOCOL_FACTORY = _protocolFactory;
        discountedFee = 50e18; // 50 USDs
        farmImplementation = address(new Demeter_CamelotFarm());
    }

    /// @notice Deploys a new Camelot farm.
    /// @param _data Data for deployment.
    /// @return The address of the newly created farm.
    function createFarm(FarmData memory _data)
        external
        nonReentrant
        returns (address)
    {
        _isNonZeroAddr(_data.farmAdmin);
        Demeter_CamelotFarm farmInstance = Demeter_CamelotFarm(
            Clones.clone(farmImplementation)
        );

        address pairPool = validatePool(
            _data.camelotPoolData.tokenA,
            _data.camelotPoolData.tokenB
        );

        farmInstance.initialize(
            _data.farmStartTime,
            _data.cooldownPeriod,
            pairPool,
            _data.rewardData
        );
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee(_data.camelotPoolData.tokenA, _data.camelotPoolData.tokenB);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        return farm;
    }

    /// @notice Validates a Camelot pool and retrieves the pair address.
    /// @param _tokenA The address of token A in the pool.
    /// @param _tokenB The address of token B in the pool.
    /// @return pool The address of the Camelot pool pair.
    function validatePool(address _tokenA, address _tokenB)
        public
        view
        returns (address pool)
    {
        pool = ICamelotFactory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _isNonZeroAddr(pool);
        return pool;
    }
}
