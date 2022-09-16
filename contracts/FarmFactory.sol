pragma solidity 0.8.10;
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

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract FarmFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public feeReceiver;
    address public feeToken;
    uint256 public feeAmount;
    address[] public farms;
    address[] public deployerList;
    mapping(address => bool) public farmRegistered;
    mapping(address => bool) public deployerRegistered;

    event FeeCollected(address token, uint256 amount);
    event FarmRegistered(address farm, address creator);
    event FarmDeployerRegistered(address deployer);
    event FarmDeployerRemoved(address deployer);
    event FeeParamsUpdated(address receiver, address token, uint256 amount);

    // Disable initialization for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice constructor
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    function initialize(
        address _feeReceiver,
        address _feeToken,
        uint256 _feeAmount
    ) external initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        updateFeeParams(_feeReceiver, _feeToken, _feeAmount);
    }

    /// @notice Register a farm created by registered Deployer
    /// @dev Only registered deployer can register a farm.
    /// @param _farm Address of the created farm contract
    /// @param _creator Address of the farm creator
    /// @param _collectFee Flag stating if fee collection is required
    function registerFarm(
        address _farm,
        address _creator,
        bool _collectFee
    ) external {
        require(deployerRegistered[msg.sender], "Deployer not registered");
        if (_collectFee) {
            IERC20Upgradeable(feeToken).safeTransferFrom(
                _creator,
                feeReceiver,
                feeAmount
            );
            emit FeeCollected(feeToken, feeAmount);
        }
        farms.push(_farm);
        farmRegistered[_farm] = true;
        emit FarmRegistered(_farm, _creator);
    }

    /// @notice Register a new farm deployer.
    /// @param  _deployer Address of deployer to be registered
    function registerFarmDeployer(address _deployer) external onlyOwner {
        _isNonZeroAddr(_deployer);
        require(!deployerRegistered[_deployer], "Deployer already registered");
        deployerList.push(_deployer);
        deployerRegistered[_deployer] = true;
        emit FarmDeployerRegistered(_deployer);
    }

    /// @notice Remove an existing deployer from factory
    /// @param _id of the deployer to be removed (0 index based)
    function removeDeployer(uint16 _id) external onlyOwner {
        require(_id < deployerList.length, "Invalid deployer id");
        uint256 numDeployers = deployerList.length;
        address deployer = deployerList[_id];
        delete deployerRegistered[deployer];
        deployerList[_id] = deployerList[numDeployers - 1];
        deployerList.pop();

        emit FarmDeployerRemoved(deployer);
    }

    /// @notice Get list of registered deployer
    /// @return Returns array of registered deployer addresses
    function getFarmDeployerList() external view returns (address[] memory) {
        return deployerList;
    }

    /// @notice Get list of farms created via registered deployer
    /// @return Returns array of farm addresses
    function getFarmList() external view returns (address[] memory) {
        return farms;
    }

    /// @notice Update the fee params for factory
    /// @param _receiver feeReceiver address
    /// @param _feeToken token address for fee
    /// @param _amount amount of token to be collected
    function updateFeeParams(
        address _receiver,
        address _feeToken,
        uint256 _amount
    ) public onlyOwner {
        _isNonZeroAddr(_receiver);
        _isNonZeroAddr(_feeToken);
        require(_amount > 0, "Fee can not be 0");
        feeReceiver = _receiver;
        feeToken = _feeToken;
        feeAmount = _amount;
        emit FeeParamsUpdated(_receiver, _feeToken, _amount);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
