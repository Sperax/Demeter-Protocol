pragma solidity 0.8.10;

import "../interfaces/IFarmFactory.sol";
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
    uint256 public discountedFee;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedDeployer;

    event PrivilegeUpdated(address deployer, bool privilege);
    event DiscountedFeeUpdated(
        uint256 oldDiscountedFee,
        uint256 newDiscountedFee
    );

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
    /// @param _discountedFee New desired discount on Spa/ USDs farms
    /// @dev _discountedFee cannot be more than 100
    function updateDiscountedFee(uint256 _discountedFee) external onlyOwner {
        emit DiscountedFeeUpdated(discountedFee, _discountedFee);
        discountedFee = _discountedFee;
    }

    /// @notice A public view function to calculate fees
    /// @param _tokenA address of token A
    /// @param _tokenB address of token B
    /// @notice Order does not matter
    /// @return Fees to be paid in feeToken set in FarmFactory (mostly USDs)
    function calculateFees(address _tokenA, address _tokenB)
        external
        view
        override
        returns (
            address,
            address,
            uint256,
            bool
        )
    {
        _isNonZeroAddr(_tokenA);
        _isNonZeroAddr(_tokenB);
        require(_tokenA != _tokenB, "Invalid token pair");
        return _calculateFees(_tokenA, _tokenB);
    }

    function validatePool(address _tokenA, address _tokenB)
        public
        returns (address pool)
    {
        pool = IUniswapV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _isNonZeroAddr(pool);
        return pool;
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from sfarmFactory.
    function _collectFee(address _tokenA, address _tokenB) internal override {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount,
            bool claimable
        ) = _calculateFees(_tokenA, _tokenB);
        if (feeAmount > 0) {
            IERC20(feeToken).safeTransferFrom(
                msg.sender,
                feeReceiver,
                feeAmount
            );
            emit FeeCollected(msg.sender, feeToken, feeAmount, claimable);
        }
    }

    /// @notice An internal function to calculate fees
    /// @notice and return feeReceiver, feeToken, feeAmount and claimable
    function _calculateFees(address _tokenA, address _tokenB)
        internal
        view
        returns (
            address,
            address,
            uint256,
            bool
        )
    {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount
        ) = IFarmFactory(factory).getFeeParams();
        if (isPrivilegedDeployer[msg.sender]) {
            // No fees for privileged deployers
            feeAmount = 0;
            return (feeReceiver, feeToken, feeAmount, false);
        }
        if (!_validateToken(_tokenA) && !_validateToken(_tokenB)) {
            // No discount because neither of the token is SPA or USDs
            return (feeReceiver, feeToken, feeAmount, false);
        } else {
            // DiscountedFee if either of the token is SPA or USDs
            // This fees is claimable
            return (feeReceiver, feeToken, discountedFee, true);
        }
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) private pure returns (bool) {
        return _token == SPA || _token == USDs;
    }
}
