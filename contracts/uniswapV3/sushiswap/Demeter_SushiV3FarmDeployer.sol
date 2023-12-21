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

import {BaseUniV3FarmDeployer, BaseFarmDeployer, IFarmFactory} from "../BaseUniV3FarmDeployer.sol";
import {Demeter_SushiV3Farm} from "./Demeter_SushiV3Farm.sol";
import {RewardTokenData, UniswapPoolData} from "../BaseUniV3Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Demeter_SushiV3FarmDeployer is BaseUniV3FarmDeployer {
    string public constant DEPLOYER_NAME = "Demeter_SushiV3FarmDeployer_v3";

    constructor(address _factory, address _uniswapUtils, address _nfpmUtils) BaseFarmDeployer(_factory) {
        _isNonZeroAddr(_uniswapUtils);
        _isNonZeroAddr(_nfpmUtils);

        farmImplementation = address(new Demeter_SushiV3Farm());
        uniswapUtils = _uniswapUtils;
        nfpmUtils = _nfpmUtils;
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _isNonZeroAddr(_data.farmAdmin);
        Demeter_SushiV3Farm farmInstance = Demeter_SushiV3Farm(Clones.clone(farmImplementation));
        farmInstance.initialize({
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _uniswapPoolData: _data.uniswapPoolData,
            _rwdTokenData: _data.rewardData,
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
