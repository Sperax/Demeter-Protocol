pragma solidity 0.8.10;

import "./FarmFactory.sol";

import {UniswapFarmV1, RewardTokenData, UniswapPoolData} from "./UniswapFarmV1.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract UniswapFarmV1Deployer {
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

    string public constant DEPLOYER_NAME = "UniswapV3FarmDeployer";
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public immutable factory;
    // Stores the address of farm implementation.
    address public immutable implementation;

    event FarmCreated(address farm, address creator);

    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        factory = _factory;
        implementation = address(new UniswapFarmV1());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data) external returns (address) {
        _isNonZeroAddr(_data.farmAdmin);
        UniswapFarmV1 farmInstance = UniswapFarmV1(
            Clones.clone(implementation)
        );
        farmInstance.initialize(
            _data.farmStartTime,
            _data.cooldownPeriod,
            _data.uniswapPoolData,
            _data.rewardData
        );
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // A logic to check if fee collection is required for farm deployment
        // Collect fee only if neither of the token is either SPA | USDs
        bool collectFee = !_validateToken(_data.uniswapPoolData.tokenA) &&
            !_validateToken(_data.uniswapPoolData.tokenB);

        FarmFactory(factory).registerFarm(farm, msg.sender, collectFee);

        emit FarmCreated(farm, msg.sender);
        return farm;
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) private pure returns (bool) {
        return _token == SPA || _token == USDs;
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
