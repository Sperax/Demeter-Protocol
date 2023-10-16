// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import {BaseFarm} from "../contracts/BaseFarm.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../test/utils/DeploymentSetup.sol";
import { FarmFactory } from "../../contracts/farmFactory.sol";
import { BaseFarmDeployer } from "../../contracts/BaseFarmDeployer.sol";
import { BaseFarm, RewardTokenData } from "../../contracts/BaseFarm.sol";
import { Demeter_BalancerFarm } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm.sol";
import { Demeter_BalancerFarm_Deployer } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";
import {console} from "forge-std/console.sol";
contract BaseFarmTest is PreMigrationSetup {


    function test_noLockupFarm_deposit() public useActor(0){

        balancerFarm.cooldownPeriod();
    }
}
