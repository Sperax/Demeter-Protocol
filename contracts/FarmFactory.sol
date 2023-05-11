pragma solidity 0.8.16;
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

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract FarmFactory is OwnableUpgradeable {
    address public feeReceiver;
    address public feeToken;
    uint256 public feeAmount;
    address[] public farms;
    address[] public deployerList;
    mapping(address => bool) public farmRegistered;
    mapping(address => bool) public deployerRegistered;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedDeployer;

    event FarmRegistered(
        address indexed farm,
        address indexed creator,
        address indexed deployer
    );
    event FarmDeployerRegistered(address deployer);
    event FarmDeployerRemoved(address deployer);
    event FeeParamsUpdated(address receiver, address token, uint256 amount);
    event PrivilegeUpdated(address deployer, bool privilege);

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
        updateFeeParams(_feeReceiver, _feeToken, _feeAmount);
    }

    /// @notice Register a farm created by registered Deployer
    /// @dev Only registered deployer can register a farm.
    /// @param _farm Address of the created farm contract
    /// @param _creator Address of the farm creator
    function registerFarm(address _farm, address _creator) external {
        require(deployerRegistered[msg.sender], "Deployer not registered");
        farms.push(_farm);
        farmRegistered[_farm] = true;
        emit FarmRegistered(_farm, _creator, msg.sender);
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
        uint256 numDeployer = deployerList.length;
        require(_id < numDeployer, "Invalid deployer id");
        address deployer = deployerList[_id];
        delete deployerRegistered[deployer];
        deployerList[_id] = deployerList[numDeployer - 1];
        deployerList.pop();

        emit FarmDeployerRemoved(deployer);
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

    /// @notice Get all the fee parameters for creating farm.
    /// @return Returns FeeReceiver, feeToken address and feeTokenAmt.
    function getFeeParams()
        external
        view
        returns (
            address,
            address,
            uint256
        )
    {
        return (feeReceiver, feeToken, feeAmount);
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
