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

import {BaseFarmDeployer, SafeERC20, IERC20, IFarmFactory} from "../../BaseFarmDeployer.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {Demeter_E20_farm} from "./Demeter_E20_farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RewardTokenData} from "../BaseE20Farm.sol";

contract Demeter_UniV2FarmDeployer is BaseFarmDeployer, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // @dev the token Order is not important
    struct PoolData {
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
        PoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable PROTOCOL_FACTORY;
    // solhint-disable-next-line var-name-mixedcase
    string public DEPLOYER_NAME;

    constructor(address _factory, address _protocolFactory, string memory _deployerName) BaseFarmDeployer(_factory) {
        _isNonZeroAddr(_protocolFactory);
        PROTOCOL_FACTORY = _protocolFactory;
        DEPLOYER_NAME = _deployerName;
        farmImplementation = address(new Demeter_E20_farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _isNonZeroAddr(_data.farmAdmin);
        Demeter_E20_farm farmInstance = Demeter_E20_farm(Clones.clone(farmImplementation));

        address pairPool = validatePool(_data.camelotPoolData.tokenA, _data.camelotPoolData.tokenB);

        farmInstance.initialize({
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _factory: FACTORY,
            _farmToken: pairPool,
            _rwdTokenData: _data.rewardData
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required
        _collectFee();
        IFarmFactory(FACTORY).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    function validatePool(address _tokenA, address _tokenB) public view returns (address pool) {
        pool = IUniswapV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _isNonZeroAddr(pool);
        return pool;
    }
}
