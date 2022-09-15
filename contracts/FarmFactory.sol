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

import "./interfaces/IFarmDeployer.sol";

contract FarmFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public feeReceiver;
    address public feeToken;
    uint256 public feeAmount;
    address[] public farms;
    string[] public deployerList;

    mapping(string => address) public farmDeployer;

    event FeeCollected(address token, uint256 amount);
    event FarmCreated(address farm, address creator, string farmType);
    event FarmDeployerRegistered(string farmType, address deployer);
    event FarmDeployerRemoved(string farmType);
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

    /// @notice Creates a new farm
    /// @param _farmType Farm to deploy.
    /// @param _data Encoded farm deployment params.
    function createFarm(string memory _farmType, bytes memory _data)
        external
        nonReentrant
        returns (address)
    {
        address deployer = farmDeployer[_farmType];
        require(deployer != address(0), "Invalid farm type");
        (address farm, bool collectFee) = IFarmDeployer(deployer).deploy(_data);
        if (collectFee) {
            _collectFees();
        }
        farms.push(farm);
        emit FarmCreated(farm, msg.sender, _farmType);
        return farm;
    }

    /// @notice Register a new farm deployer.
    /// @param _farmType a unique identifier for a farm (ex : UniswapV3FarmV1)
    function registerFarmDeployer(string memory _farmType, address _deployer)
        external
        onlyOwner
    {
        _isNonZeroAddr(_deployer);
        require(
            farmDeployer[_farmType] == address(0),
            "Deployer already exists"
        );
        deployerList.push(_farmType);
        farmDeployer[_farmType] = _deployer;
        emit FarmDeployerRegistered(_farmType, _deployer);
    }

    /// @notice Remove an existing deployer from factory
    /// @param _id of the deployer to be removed
    function removeDeployer(uint16 _id) external onlyOwner {
        require(_id < deployerList.length, "Invalid deployer id");
        uint256 numDeployers = deployerList.length;
        string memory deployer = deployerList[_id];
        delete farmDeployer[deployer];
        deployerList[_id] = deployerList[numDeployers - 1];
        deployerList.pop();

        emit FarmDeployerRemoved(deployer);
    }

    function getFarmDeployerList() external view returns (string[] memory) {
        return deployerList;
    }

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

    /// @notice Collect fees for farm creation.
    /// @dev Collect fees only if validated by the farm deployer.
    function _collectFees() private {
        IERC20Upgradeable(feeToken).safeTransferFrom(
            msg.sender,
            feeReceiver,
            feeAmount
        );
        emit FeeCollected(feeToken, feeAmount);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
