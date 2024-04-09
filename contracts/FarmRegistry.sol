// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@***@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(****@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@((******@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(((*******@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@((((********@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@(((((********@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@(((((((********@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@(((((((/*******@@@@@@@ //
// @@@@@@@@@@&*****@@@@@@@@@@(((((((*******@@@@@ //
// @@@@@@***************@@@@@@@(((((((/*****@@@@ //
// @@@@********************@@@@@@@(((((((****@@@ //
// @@@************************@@@@@@(/((((***@@@ //
// @@@**************@@@@@@@@@***@@@@@@(((((**@@@ //
// @@@**************@@@@@@@@*****@@@@@@*((((*@@@ //
// @@@**************@@@@@@@@@@@@@@@@@@@**(((@@@@ //
// @@@@***************@@@@@@@@@@@@@@@@@**((@@@@@ //
// @@@@@****************@@@@@@@@@@@@@****(@@@@@@ //
// @@@@@@@*****************************/@@@@@@@@ //
// @@@@@@@@@@************************@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@***************@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Farm Registry contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract tracks fee details, privileged deployers, deployed farms and farm deployers.
contract FarmRegistry is OwnableUpgradeable {
    address public feeReceiver;
    address public feeToken;
    uint256 public feeAmount;
    uint256 public extensionFeePerDay;
    address[] public farms;
    address[] public deployerList;
    mapping(address => bool) public farmRegistered;
    mapping(address => bool) public deployerRegistered;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedDeployer;

    // Events.
    event FarmRegistered(address indexed farm, address indexed creator, address indexed deployer);
    event FarmDeployerUpdated(address deployer, bool registered);
    event FeeParamsUpdated(address receiver, address token, uint256 amount, uint256 extensionFeePerDay);
    event PrivilegeUpdated(address deployer, bool privilege);

    // Custom Errors.
    error DeployerNotRegistered();
    error DeployerAlreadyRegistered();
    error InvalidDeployerId();
    error PrivilegeSameAsDesired();
    error InvalidAddress();

    // Disable initialization for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice constructor
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    /// @param _feeReceiver Receiver of the fees.
    /// @param _extensionFeePerDay Extension fee per day.
    function initialize(address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay)
        external
        initializer
    {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        updateFeeParams(_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay);
    }

    /// @notice Register a farm created by registered Deployer.
    /// @dev Only registered deployer can register a farm.
    /// @param _farm Address of the created farm contract
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
    /// @param  _deployer Address of deployer to be registered.
    function registerFarmDeployer(address _deployer) external onlyOwner {
        _validateNonZeroAddr(_deployer);
        if (deployerRegistered[_deployer]) {
            revert DeployerAlreadyRegistered();
        }
        deployerList.push(_deployer);
        deployerRegistered[_deployer] = true;
        emit FarmDeployerUpdated(_deployer, true);
    }

    /// @notice Remove an existing deployer from registry.
    /// @param _id of the deployer to be removed (0 index based).
    function removeDeployer(uint16 _id) external onlyOwner {
        uint256 numDeployer = deployerList.length;
        if (_id >= numDeployer) {
            revert InvalidDeployerId();
        }
        address deployer = deployerList[_id];
        delete deployerRegistered[deployer];
        deployerList[_id] = deployerList[numDeployer - 1];
        deployerList.pop();

        emit FarmDeployerUpdated(deployer, false);
    }

    /// @notice Function to add/ remove privileged deployer.
    /// @param _deployer Deployer(address) to add to privileged deployers list.
    /// @param _privilege Privilege(bool) whether true or false.
    /// @dev Only callable by the owner.
    function updatePrivilege(address _deployer, bool _privilege) external onlyOwner {
        if (isPrivilegedDeployer[_deployer] == _privilege) {
            revert PrivilegeSameAsDesired();
        }
        isPrivilegedDeployer[_deployer] = _privilege;
        emit PrivilegeUpdated(_deployer, _privilege);
    }

    /// @notice Get list of registered deployer.
    /// @return Returns array of registered deployer addresses.
    function getFarmDeployerList() external view returns (address[] memory) {
        return deployerList;
    }

    /// @notice Get list of farms created via registered deployer.
    /// @return Returns array of farm addresses.
    function getFarmList() external view returns (address[] memory) {
        return farms;
    }

    /// @notice Get all the fee parameters for creating farm.
    /// @param _deployerAccount The account creating the farm.
    /// @return Returns FeeReceiver, feeToken address, feeTokenAmt and extensionFeePerDay.
    /// @dev It returns fee amount as 0 if deployer account is privileged.
    function getFeeParams(address _deployerAccount) external view returns (address, address, uint256, uint256) {
        if (isPrivilegedDeployer[_deployerAccount]) {
            return (feeReceiver, feeToken, 0, 0);
        }
        return (feeReceiver, feeToken, feeAmount, extensionFeePerDay);
    }

    /// @notice Update the fee params for registry.
    /// @param _receiver FeeReceiver address.
    /// @param _feeToken Token address for fee.
    /// @param _amount Amount of token to be collected.
    /// @param _extensionFeePerDay Extension fee per day.
    function updateFeeParams(address _receiver, address _feeToken, uint256 _amount, uint256 _extensionFeePerDay)
        public
        onlyOwner
    {
        _validateNonZeroAddr(_receiver);
        _validateNonZeroAddr(_feeToken);
        feeReceiver = _receiver;
        feeToken = _feeToken;
        feeAmount = _amount;
        extensionFeePerDay = _extensionFeePerDay;
        emit FeeParamsUpdated(_receiver, _feeToken, _amount, _extensionFeePerDay);
    }

    /// @notice Validate address.
    function _validateNonZeroAddr(address _addr) private pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
