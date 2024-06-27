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
import {IFarmRegistry} from "./interfaces/IFarmRegistry.sol";

/// @title Farm Registry contract of Demeter Protocol.
/// @author Sperax Foundation.
/// @notice This contract tracks fee details, privileged deployers, deployed farms and farm deployers.
contract FarmRegistry is IFarmRegistry, OwnableUpgradeable {
    address[] internal farms;
    address[] internal deployerList;

    address public feeReceiver;
    address public feeToken;
    uint256 public feeAmount;
    uint256 public extensionFeePerDay;
    mapping(address => bool) public farmRegistered;
    mapping(address => bool) public deployerRegistered;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedUser;

    // Disable initialization for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IFarmRegistry
    function initialize(address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay)
        external
        initializer
    {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        updateFeeParams(_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay);
    }

    /// @inheritdoc IFarmRegistry
    function registerFarm(address _farm, address _creator) external {
        _validateNonZeroAddr(_farm);
        if (!deployerRegistered[msg.sender]) {
            revert DeployerNotRegistered();
        }
        if (farmRegistered[_farm]) {
            revert FarmAlreadyRegistered();
        }

        farms.push(_farm);
        farmRegistered[_farm] = true;
        emit FarmRegistered(_farm, _creator, msg.sender);
    }

    /// @inheritdoc IFarmRegistry
    function registerFarmDeployer(address _deployer) external onlyOwner {
        _validateNonZeroAddr(_deployer);
        if (deployerRegistered[_deployer]) {
            revert DeployerAlreadyRegistered();
        }
        deployerList.push(_deployer);
        deployerRegistered[_deployer] = true;
        emit FarmDeployerUpdated(_deployer, true);
    }

    /// @inheritdoc IFarmRegistry
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

    /// @inheritdoc IFarmRegistry
    function updatePrivilege(address _user, bool _privilege) external onlyOwner {
        if (isPrivilegedUser[_user] == _privilege) {
            revert PrivilegeSameAsDesired();
        }
        isPrivilegedUser[_user] = _privilege;
        emit PrivilegeUpdated(_user, _privilege);
    }

    /// @inheritdoc IFarmRegistry
    function getFarmDeployerList() external view returns (address[] memory) {
        return deployerList;
    }

    /// @inheritdoc IFarmRegistry
    function getFarmList() external view returns (address[] memory) {
        return farms;
    }

    /// @inheritdoc IFarmRegistry
    function getFeeParams(address _user) external view returns (address, address, uint256, uint256) {
        if (isPrivilegedUser[_user]) {
            return (feeReceiver, feeToken, 0, 0);
        }
        return (feeReceiver, feeToken, feeAmount, extensionFeePerDay);
    }

    /// @inheritdoc IFarmRegistry
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
