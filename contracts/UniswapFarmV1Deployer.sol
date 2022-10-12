pragma solidity 0.8.10;

import "./../interfaces/IFarmFactory.sol";
import "./BaseFarmDeployer.sol";
import {UniswapFarmV1, RewardTokenData, UniswapPoolData} from "./UniswapFarmV1.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract UniswapFarmV1Deployer is BaseFarmDeployer, ReentrancyGuard {
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

    constructor(address _factory) {
        owner = msg.sender;
        _isNonZeroAddr(_factory);
        factory = _factory;
        farmImplementation = address(new UniswapFarmV1());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    function createFarm(FarmData memory _data)
        external
        nonReentrant
        returns (address)
    {
        _isNonZeroAddr(_data.farmAdmin);
        UniswapFarmV1 farmInstance = UniswapFarmV1(
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
        // A logic to check if fee collection is required for farm deployment
        // Collect fee only if neither of the token is either SPA | USDs
        if (!isPrivilegedDeployer[msg.sender]) {
            if (
                !_validateToken(_data.uniswapPoolData.tokenA) &&
                !_validateToken(_data.uniswapPoolData.tokenB)
            ) {
                // No discount because none of the tokens are SPA or USDs
                _collectFee(0);
            } else {
                // 80% discount if either of the tokens are SPA or USDs
                _collectFee(80);
            }
        }
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice A function to add/ remove privileged deployer
    /// @param _deployer Deployer(address) to add to privileged deployers list
    /// @param _privilege Privilege(bool) whether true or false
    /// @dev to be only called by owner
    function updatePrivilege(address _deployer, bool _privilege) external {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        require(
            isPrivilegedDeployer[_deployer] != _privilege,
            "Privilege is same as desired"
        );
        isPrivilegedDeployer[_deployer] = _privilege;
        emit PrivilegeUpdated(_deployer, _privilege);
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) private pure returns (bool) {
        return _token == SPA || _token == USDs;
    }
}
