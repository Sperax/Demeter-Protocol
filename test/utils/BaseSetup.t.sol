// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Farm} from "../../contracts/Farm.sol";
import {FarmRegistry} from "../../contracts/FarmRegistry.sol";
import {FarmDeployer} from "../../contracts/FarmDeployer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract BaseSetup is Test {
    // Define global constants | Test config
    // @dev Make it 0 to test on latest
    uint256 public constant NUM_ACTORS = 12;
    uint256 public constant GAS_LIMIT = 1000000000;

    // Define Demeter constants here
    address internal PROXY_OWNER;
    address internal FARM_REGISTRY_OWNER;
    address internal PROXY_ADMIN;
    address internal FARM_REGISTRY;

    // Define fork networks
    uint256 internal forkCheck;

    address public owner;
    address public registry;
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
        owner = actors[4];
        FARM_REGISTRY_OWNER = actors[5];
    }
}
