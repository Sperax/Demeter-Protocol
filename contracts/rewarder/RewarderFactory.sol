// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";

/// @title Demeter Rewarder Manager contract.
/// @author Sperax Foundation.
/// @notice This contract deploys new rewarders and keeps track of them.
contract RewarderFactory is IRewarderFactory, Ownable {
    address public oracle;
    address public rewarderImplementation;

    /// @notice Constructor.
    /// @param _oracle Address of the master price oracle of USDs.
    constructor(address _oracle) Ownable(msg.sender) {
        updateOracle(_oracle);
        rewarderImplementation = address(new Rewarder());
    }

    /// @inheritdoc IRewarderFactory
    function deployRewarder(address _rwdToken) external returns (address rewarder) {
        rewarder = Clones.clone(rewarderImplementation);
        Rewarder(rewarder).initialize(_rwdToken, oracle, msg.sender);
        emit RewarderDeployed(_rwdToken, msg.sender, rewarder);
    }

    /// @inheritdoc IRewarderFactory
    function updateRewarderImplementation(address _newRewarderImplementation) external onlyOwner {
        _validateNonZeroAddr(_newRewarderImplementation);
        rewarderImplementation = _newRewarderImplementation;

        emit RewarderImplementationUpdated(_newRewarderImplementation);
    }

    /// @inheritdoc IRewarderFactory
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
