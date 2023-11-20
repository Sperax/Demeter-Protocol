// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFarmFactory} from "./interfaces/IFarmFactory.sol";

/// @title BaseFarmDeployer contract of Demeter Protocol
/// @notice Exposes base functionalities which will be useful in every deployer
/// @author Sperax Foundation
abstract contract BaseFarmDeployer is Ownable {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public immutable FACTORY;
    // Stores the address of farmImplementation.
    address public farmImplementation;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(address indexed creator, address token, uint256 amount);
    event FarmImplementationUpdated(address newFarmImplementation);

    // Custom Errors
    error InvalidAddress();

    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        FACTORY = _factory;
    }

    /// @notice Update farm implementation's address
    /// @dev only callable by owner
    /// @param _newFarmImplementation New farm implementation's address
    function updateFarmImplementation(address _newFarmImplementation) external onlyOwner {
        farmImplementation = _newFarmImplementation;
        emit FarmImplementationUpdated(_newFarmImplementation);
    }

    /// @notice A public view function to get fees from Farm Factory
    /// @return feeReceiver of feeToken in feeAmount
    function getFees(address _deployerAccount)
        external
        view
        returns (address feeReceiver, address feeToken, uint256 feeAmount, uint256 extensionFeePerDay)
    {
        (feeReceiver, feeToken, feeAmount, extensionFeePerDay) = IFarmFactory(FACTORY).getFeeParams(_deployerAccount);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
    function _collectFee() internal virtual {
        // Here msg.sender would be the deployer/creator of the farm which will be checked in privileged deployer list
        (address feeReceiver, address feeToken, uint256 feeAmount,) = IFarmFactory(FACTORY).getFeeParams(msg.sender);
        if (feeAmount != 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
            emit FeeCollected(msg.sender, feeToken, feeAmount);
        }
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
