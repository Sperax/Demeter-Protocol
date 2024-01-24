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
import {BaseUniV3Farm, RewardTokenData, UniswapPoolData} from "./BaseUniV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Demeter_UniV3FarmDeployer is BaseFarmDeployer, ReentrancyGuard {
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
    address public immutable UNISWAP_UTILS; // UniswapUtils (Uniswap helper) contract
    address public immutable NFPM_UTILS; // Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract

    constructor(
        address _factory,
        string memory _farmId,
        address _uniV3Factory,
        address _nfpm,
        address _uniswapUtils,
        address _nfpmUtils
    ) BaseFarmDeployer(_factory, _farmId) {
        _isNonZeroAddr(_uniV3Factory);
        _isNonZeroAddr(_nfpm);
        _isNonZeroAddr(_uniswapUtils);
        _isNonZeroAddr(_nfpmUtils);

        UNI_V3_FACTORY = _uniV3Factory;
        NFPM = _nfpm;
        UNISWAP_UTILS = _uniswapUtils;
        NFPM_UTILS = _nfpmUtils;
        farmImplementation = address(new BaseUniV3Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _isNonZeroAddr(_data.farmAdmin);

        BaseUniV3Farm farmInstance = BaseUniV3Farm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _factory: FACTORY,
            _uniswapPoolData: _data.uniswapPoolData,
            _rwdTokenData: _data.rewardData,
            _uniV3Factory: uniV3Factory,
            _nfpm: nfpm,
            _uniswapUtils: uniswapUtils,
            _nfpmUtils: nfpmUtils
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmFactory(FACTORY).registerFarm(farm, msg.sender);
        return farm;
    }
}
