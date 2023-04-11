pragma solidity 0.8.10;

import "../BaseFarmDeployer.sol";
import {Demeter_CamelotFarm, RewardTokenData} from "./Demeter_CamelotFarm.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ICamelotFactory} from "./interfaces/CamelotInterfaces.sol";

contract Demeter_CamelotFarm_Deployer is BaseFarmDeployer, ReentrancyGuard {
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

    string public constant DEPLOYER_NAME = "Demeter_CamelotFarmDeployer_v1";
    address public PROTOCOL_FACTORY;

    constructor(address _factory, address _protocolFactory) {
        _isNonZeroAddr(_factory);
        _isNonZeroAddr(_protocolFactory);
        factory = _factory;
        PROTOCOL_FACTORY = _protocolFactory;
        discountedFee = 100e18; // 100 USDs
        farmImplementation = address(new Demeter_CamelotFarm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
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
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    function validatePool(address _tokenA, address _tokenB)
        public
        returns (address pool)
    {
        pool = ICamelotFactory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _isNonZeroAddr(pool);
        return pool;
    }
}
