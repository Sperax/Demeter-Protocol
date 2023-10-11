// SPDX-License-Identifier: MIT
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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title FarmFactory
/// @dev A contract that allows registered deployers to create farms with fees.
contract FarmFactory is OwnableUpgradeable {
    address public feeReceiver; // Address to receive the creation fees.
    address public feeToken; // Token used for the creation fees.
    uint256 public feeAmount; // Amount of the creation fee.
    address[] public farms; // List of created farm contracts.
    address[] public deployerList; // List of registered deployers.
    mapping(address => bool) public farmRegistered; // Mapping to check if a farm is registered.
    mapping(address => bool) public deployerRegistered; // Mapping to check if a deployer is registered.
    mapping(address => bool) public isPrivilegedDeployer; // Mapping to check if a deployer is privileged.

    event FarmRegistered(
        address indexed farm,
        address indexed creator,
        address indexed deployer
    );
    event FarmDeployerRegistered(address deployer);
    event FarmDeployerRemoved(address deployer);
    event FeeParamsUpdated(address receiver, address token, uint256 amount);
    event PrivilegeUpdated(address deployer, bool privilege);

    // Custom Errors
    error DeployerNotRegistered();
    error DeployerAlreadyRegistered();
    error InvalidDeployerId();
    error PrivilegeSameAsDesired();
    error FeeCannotBeZero();
    error InvalidAddress();

    /// @dev Disable initialization for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract with fee parameters.
    /// @param _feeReceiver The address that will receive the creation fees.
    /// @param _feeToken The token used for the creation fees.
    /// @param _feeAmount The amount of the creation fee.
    function initialize(
        address _feeReceiver,
        address _feeToken,
        uint256 _feeAmount
    ) external initializer {
        OwnableUpgradeable.__Ownable_init();
        updateFeeParams(_feeReceiver, _feeToken, _feeAmount);
    }

    /// @notice Register a farm created by a registered deployer.
    /// @param _farm Address of the created farm contract.
    /// @param _creator Address of the farm creator.
    function registerFarm(address _farm, address _creator) external {
        if (!deployerRegistered[msg.sender]) {
            revert DeployerNotRegistered();
        }
        farms.push(_farm);
        farmRegistered[_farm] = true;
        emit FarmRegistered(_farm, _creator, msg.sender);
    }

    /// @notice Register a new farm deployer.
    /// @param _deployer Address of the deployer to be registered.
    function registerFarmDeployer(address _deployer) external onlyOwner {
        _isNonZeroAddr(_deployer);
        if (deployerRegistered[_deployer]) {
            revert DeployerAlreadyRegistered();
        }
        deployerList.push(_deployer);
        deployerRegistered[_deployer] = true;
        emit FarmDeployerRegistered(_deployer);
    }

    /// @notice Remove an existing deployer from the factory.
    /// @param _id The index of the deployer to be removed (0-indexed).
    function removeDeployer(uint16 _id) external onlyOwner {
        uint256 numDeployer = deployerList.length;
        if (_id >= numDeployer) {
            revert InvalidDeployerId();
        }
        address deployer = deployerList[_id];
        delete deployerRegistered[deployer];
        deployerList[_id] = deployerList[numDeployer - 1];
        deployerList.pop();

        emit FarmDeployerRemoved(deployer);
    }

    /// @notice Add or remove privilege for a deployer.
    /// @param _deployer The address of the deployer.
    /// @param _privilege True to grant privilege, false to revoke it.
    /// @dev to be only called by owner
    function updatePrivilege(address _deployer, bool _privilege)
        external
        onlyOwner
    {
        if (isPrivilegedDeployer[_deployer] == _privilege) {
            revert PrivilegeSameAsDesired();
        }
        isPrivilegedDeployer[_deployer] = _privilege;
        emit PrivilegeUpdated(_deployer, _privilege);
    }

    /// @notice Get the list of registered deployers.
    /// @return An array of registered deployer addresses.
    function getFarmDeployerList() external view returns (address[] memory) {
        return deployerList;
    }

    /// @notice Get the list of farms created via registered deployers.
    /// @return An array of farm addresses.
    function getFarmList() external view returns (address[] memory) {
        return farms;
    }

    /// @notice Get all the fee parameters for creating farms.
    /// @return The fee receiver address, fee token address, and fee amount.
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

    /// @notice Update the fee parameters for the factory.
    /// @dev This function allows the contract owner to update the fee parameters for the factory.
    /// @param _receiver The address where the collected fees will be transferred to.
    /// @param _feeToken The address of the token that will be collected as a fee.
    /// @param _amount The amount of the fee token to be collected for each factory operation.
    function updateFeeParams(
        address _receiver,
        address _feeToken,
        uint256 _amount
    ) public onlyOwner {
        _isNonZeroAddr(_receiver);
        _isNonZeroAddr(_feeToken);
        if (_amount == 0) {
            revert FeeCannotBeZero();
        }
        feeReceiver = _receiver;
        feeToken = _feeToken;
        feeAmount = _amount;
        emit FeeParamsUpdated(_receiver, _feeToken, _amount);
    }

    /// @dev Internal function to validate a non-zero address.
    function _isNonZeroAddr(address _addr) private pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
