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

    address public constant FEE_RECEIVER =
        0x5b12d9846F8612E439730d18E1C12634753B1bF1;

    address public feeToken;
    uint256 public feeAmount;
    uint256 public numFarmCreated;
    address[] public farms;
    string[] public deployerList;

    mapping(string => address) public farmDeployer;

    event FeeCollected(address token, uint256 amount);
    event FarmCreated(address creator, address farm);
    event FarmDeployerRegistered(string farmType, address deployer);

    // Disable initialization for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice constructor
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    function initialize(address _feeToken, uint256 _feeAmount)
        external
        initializer
    {
        _isNonZeroAddr(_feeToken);
        require(_feeAmount != 0, "Fee cannot be zero");
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        feeToken = _feeToken;
        feeAmount = _feeAmount;
    }

    /// @notice Creates a new farm
    /// @param _farmType Farm to deploy.
    /// @param _data Encoded farm deployment params.
    function createFarm(string memory _farmType, bytes memory _data)
        external
        nonReentrant
        returns (address)
    {
        (address farm, bool collectFee) = IFarmDeployer(farmDeployer[_farmType])
            .deploy(_data);
        if (collectFee) {
            _collectFees();
        }
        farms.push(farm);
        numFarmCreated += 1;
        emit FarmCreated(msg.sender, farm);
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
        farmDeployer[_farmType] = _deployer;
        deployerList.push(_farmType);
    }

    function getFarmDeployerList() external view returns (string[] memory) {
        return deployerList;
    }

    /// @notice Collect fees for farm creation.
    /// @dev Collect fees only if validated by the farm deployer.
    function _collectFees() private {
        IERC20Upgradeable(feeToken).safeTransferFrom(
            msg.sender,
            FEE_RECEIVER,
            feeAmount
        );
        emit FeeCollected(feeToken, feeAmount);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
