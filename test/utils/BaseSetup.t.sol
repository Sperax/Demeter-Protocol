// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {BaseFarm} from "../../contracts/BaseFarm.sol";
import {FarmFactory} from "../../contracts/FarmFactory.sol";
import {BaseFarmDeployer} from "../../contracts/BaseFarmDeployer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract BaseSetup is Test {
    // Define global constants | Test config
    // @dev Make it 0 to test on latest
    uint256 public constant NUM_ACTORS = 6;
    uint256 public constant GAS_LIMIT = 1000000000;

    // Define Demeter constants here
    address internal PROXY_OWNER;
    address internal PROXY_ADMIN;
    address internal DEMETER_FACTORY;

    // Define fork networks
    uint256 internal forkCheck;

    address public owner;
    address[] public actors;
    address internal currentActor;

    /// @notice Get a pre-set address for prank
    /// @param actorIndex Index of the actor
    modifier useActor(uint256 actorIndex) {
        currentActor = actors[bound(actorIndex, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Start a prank session with a known user addr
    modifier useKnownActor(address user) {
        currentActor = user;
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Initialize global test configuration.
    function setUp() public virtual {
        /// @dev Initialize actors for testing.
        string memory mnemonic = vm.envString("TEST_MNEMONIC");
        for (uint32 i = 0; i < NUM_ACTORS; ++i) {
            (address act,) = deriveRememberKey(mnemonic, i);
            actors.push(act);
        }
        owner = actors[0];
    }
}
