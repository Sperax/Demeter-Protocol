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

import {FarmDeployer, IFarmFactory} from "../../FarmDeployer.sol";
import {UniV3Farm, RewardTokenData, UniswapPoolData} from "./UniV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Demeter_UniV3FarmDeployer is FarmDeployer, ReentrancyGuard {
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

    /// @notice Constructor of the contract
    /// @param _factory Address of Farm Factory
    /// @param _farmId Id of the farm
    /// @param _uniV3Factory Address of UniswapV3 factory
    /// @param _nfpm Address of Uniswap NonfungiblePositionManager contract
    /// @param _uniswapUtils Address of UniswapUtils (Uniswap helper) contract
    /// @param _nfpmUtils Address of Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract
    constructor(
        address _factory,
        string memory _farmId,
        address _uniV3Factory,
        address _nfpm,
        address _uniswapUtils,
        address _nfpmUtils
    ) FarmDeployer(_factory, _farmId) {
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
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);

        UniV3Farm farmInstance = UniV3Farm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _factory: FACTORY,
            _uniswapPoolData: _data.uniswapPoolData,
            _rwdTokenData: _data.rewardData,
            _uniV3Factory: UNI_V3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NFPM_UTILS
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
