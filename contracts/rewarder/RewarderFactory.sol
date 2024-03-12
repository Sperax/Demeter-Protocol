// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Rewarder} from "./Rewarder.sol";

/// @title Demeter Rewarder Manager contract.
/// @notice This contract deploys new rewarders and keeps track of them.
/// @author Sperax Foundation
contract RewarderFactory is Ownable {
    address public oracle;
    address public rewarderImplementation;

    event OracleUpdated(address newOracle);
    event RewarderDeployed(address indexed token, address indexed manager, address rewarder);

    error InvalidAddress();

    /// @notice Constructor of this contract.
    /// @param _oracle Address of the master price oracle of USDs.
    constructor(address _oracle) Ownable() {
        updateOracle(_oracle);
        rewarderImplementation = address(new Rewarder());
    }

    /// @notice A function to deploy new rewarder.
    /// @param _rwdToken Address of the reward token for which the rewarder is to be deployed.
    /// @return rewarder Rewarder's address
    function deployRewarder(address _rwdToken) external returns (address rewarder) {
        rewarder = Clones.clone(rewarderImplementation);
        Rewarder(rewarder).initialize(_rwdToken, oracle, msg.sender);
        emit RewarderDeployed(_rwdToken, msg.sender, rewarder);
    }

    /// @notice A function to update the oracle's address.
    /// @param _newOracle Address of the new oracle.
    function updateOracle(address _newOracle) public onlyOwner {
        _validateNonZeroAddr(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice Validate address.
    /// @param _addr Address to be validated.
    function _validateNonZeroAddr(address _addr) private pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
