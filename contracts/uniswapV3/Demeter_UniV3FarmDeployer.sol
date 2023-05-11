pragma solidity 0.8.10;

import "../BaseFarmDeployer.sol";
import {Demeter_UniV3Farm, RewardTokenData, UniswapPoolData} from "./Demeter_UniV3Farm.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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

    string public constant DEPLOYER_NAME = "Demeter_UniV3FarmDeployer_v3";

    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        factory = _factory;
        discountedFee = 100e18; // 100 USDs
        farmImplementation = address(new Demeter_UniV3Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
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
