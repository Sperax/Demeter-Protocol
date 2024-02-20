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

import {FarmDeployer, IFarmRegistry} from "../../FarmDeployer.sol";
import {Demeter_CamelotV2Farm, RewardTokenData} from "./Demeter_CamelotV2Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ICamelotV2Factory} from "./interfaces/ICamelotV2.sol";

contract Demeter_CamelotV2Farm_Deployer is FarmDeployer, ReentrancyGuard {
    // @dev the token Order is not important
    struct CamelotPoolData {
        address tokenA;
        address tokenB;
    }

    // farmAdmin - Address to which ownership of farm is transferred to post deployment
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days)
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // lpTokenData - data for camelot pool.
    //                  (tokenA, tokenB)
    // rewardTokenData - [(rewardTokenAddress, tknManagerAddress), ... ]
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        CamelotPoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable PROTOCOL_FACTORY;
    address public immutable ROUTER;
    address public immutable NFT_POOL_FACTORY;

    /// @notice Constructor of the contract
    /// @param _farmRegistry Address of Farm Registry
    /// @param _farmId Id of the farm
    /// @param _protocolFactory Address of Camelot factory
    /// @param _router Address of Camelot router
    /// @param _nftPoolFactory Address of Camelot NFT pool factory
    constructor(
        address _farmRegistry,
        string memory _farmId,
        address _protocolFactory,
        address _router,
        address _nftPoolFactory
    ) FarmDeployer(_farmRegistry, _farmId) {
        _validateNonZeroAddr(_protocolFactory);
        _validateNonZeroAddr(_nftPoolFactory);

        PROTOCOL_FACTORY = _protocolFactory;
        ROUTER = _router;
        NFT_POOL_FACTORY = _nftPoolFactory;
        farmImplementation = address(new Demeter_CamelotV2Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);
        Demeter_CamelotV2Farm farmInstance = Demeter_CamelotV2Farm(Clones.clone(farmImplementation));

        address pairPool = validatePool(_data.camelotPoolData.tokenA, _data.camelotPoolData.tokenB);

        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _farmRegistry: FARM_REGISTRY,
            _camelotPairPool: pairPool,
            _rwdTokenData: _data.rewardData,
            _router: ROUTER,
            _nftPoolFactory: NFT_POOL_FACTORY
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        return farm;
    }

    function validatePool(address _tokenA, address _tokenB) public view returns (address pool) {
        pool = ICamelotV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _validateNonZeroAddr(pool);
        return pool;
    }
}
