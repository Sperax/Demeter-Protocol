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

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IFarmDeployer.sol";

contract FarmFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant feeReceiver =
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

    /// @notice constructor
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    constructor(address _feeToken, uint256 _feeAmount) {
        _isNonZeroAddr(_feeToken);
        feeToken = _feeToken;
        feeAmount = _feeAmount;
    }

    /// @notice Creates a new farm
    /// @param _farmName Farm to deploy.
    /// @param _data Encoded farm deployment params.
    function createFarm(string memory _farmName, bytes memory _data)
        external
        onlyOwner
        nonReentrant
        returns (address farm)
    {
        bool collectFee = false;
        (farm, collectFee) = IFarmDeployer(farmDeployer[_farmName]).deploy(
            _data
        );
        if (collectFee) {
            _collectFees();
        }
        farms.push(farm);
        numFarmCreated += 1;
        emit FarmCreated(msg.sender, farm);
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
    /// @dev Collect fees only if neither of the tokens are SPA | USDs.
    function _collectFees() private {
        IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
        emit FeeCollected(feeToken, feeAmount);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
