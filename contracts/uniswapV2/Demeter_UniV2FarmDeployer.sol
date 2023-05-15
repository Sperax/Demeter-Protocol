pragma solidity 0.8.16;

import "../BaseFarmDeployer.sol";
import "./interfaces/IUniswapV2Factory.sol";
import {Demeter_E20_farm, RewardTokenData} from "./Demeter_E20_farm.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
    string public DEPLOYER_NAME;

    constructor(
        address _factory,
        address _protocolFactory,
        string memory _deployerName
    ) {
        _isNonZeroAddr(_factory);
        _isNonZeroAddr(_protocolFactory);
        factory = _factory;
        PROTOCOL_FACTORY = _protocolFactory;
        DEPLOYER_NAME = _deployerName;
        discountedFee = 100e18; // 100 USDs
        farmImplementation = address(new Demeter_E20_farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data)
        external
        nonReentrant
        returns (address)
    {
        _isNonZeroAddr(_data.farmAdmin);
        Demeter_E20_farm farmInstance = Demeter_E20_farm(
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
        pool = IUniswapV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _isNonZeroAddr(pool);
        return pool;
    }
}
