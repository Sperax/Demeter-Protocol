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

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    constructor(address _factory) {
        owner = msg.sender;
        _isNonZeroAddr(_factory);
        factory = _factory;
        discountOnSpaUSDsFarms = 80;
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
        // Calculate and collect fee if required
        _collectFee(_data.uniswapPoolData.tokenA, _data.uniswapPoolData.tokenB);
        IFarmFactory(factory).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice A function to add/ remove privileged deployer
    /// @param _deployer Deployer(address) to add to privileged deployers list
    /// @param _privilege Privilege(bool) whether true or false
    /// @dev to be only called by owner
    function updatePrivilege(address _deployer, bool _privilege)
        external
        onlyOwner
    {
        require(
            isPrivilegedDeployer[_deployer] != _privilege,
            "Privilege is same as desired"
        );
        isPrivilegedDeployer[_deployer] = _privilege;
        emit PrivilegeUpdated(_deployer, _privilege);
    }

    /// @notice An external function to update discountOnSpaUSDsFarms
    /// @param _discount New desired discount on Spa/ USDs farms
    /// @dev _discount cannot be more than 100
    function updateDiscountOnSpaUSDsFarms(uint256 _discount)
        external
        onlyOwner
    {
        require(
            _discount <= MAX_DISCOUNT,
            "Invalid discount: Greater than MAX_DISCOUNT"
        );
        emit DiscountOnSpaUSDsFarmsUpdated(discountOnSpaUSDsFarms, _discount);
        discountOnSpaUSDsFarms = _discount;
    }

    /// @notice A public view function to calculate fees
    /// @param _tokenA address of token A
    /// @param _tokenB address of token B
    /// @notice Order does not matter
    /// @return Fees to be paid in feeToken set in FarmFactory (mostly USDs)
    function calculateFees(address _tokenA, address _tokenB)
        external
        view
        returns (uint256)
    {
        (, , uint256 fees, ) = _calculateFees(_tokenA, _tokenB);
        return fees;
    }
}
