// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import {BaseFarm} from "../contracts/BaseFarm.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../test/utils/DeploymentSetup.sol";

import {console} from "forge-std/console.sol";
contract BaseFarmTest is PreMigrationSetup {
    BaseFarm public base;

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        base = new BaseFarm();
        base.transferOwnership(OWNER);
    }
}
