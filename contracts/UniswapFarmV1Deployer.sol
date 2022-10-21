pragma solidity 0.8.10;

import "./../interfaces/IFarmFactory.sol";
import "./BaseFarmDeployer.sol";
import {UniswapFarmV1, RewardTokenData, UniswapPoolData} from "./UniswapFarmV1.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract UniswapFarmV1Deployer is BaseFarmDeployer, ReentrancyGuard {
    using SafeERC20 for IERC20;
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
    uint256 public discountedFee;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedDeployer;

    event PrivilegeUpdated(address deployer, bool privilege);
    event DiscountedFeeUpdated(
        uint256 oldDiscountedFee,
        uint256 newDiscountedFee
    );

    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        factory = _factory;
        discountedFee = 100e18; // 100 USDs
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
        require(_tokenA != _tokenB, "Token A and Token B cannot be same");
        return _calculateFees(_tokenA, _tokenB);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
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
            // No discount because none of the tokens are SPA or USDs
            return (feeReceiver, feeToken, feeAmount, false);
        } else {
            // DiscountedFee if either of the tokens are SPA or USDs
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
