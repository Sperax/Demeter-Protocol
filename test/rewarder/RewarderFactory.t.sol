// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Arbitrum} from "../utils/networkConfig/Arbitrum.t.sol";
import {RewarderFactory, IRewarderFactory} from "../../contracts/rewarder/RewarderFactory.sol";
import {Rewarder} from "../../contracts/rewarder/Rewarder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RewarderFactoryTest is Arbitrum {
    IRewarderFactory public rewarderFactory;
    address public rewardManager;

    function setUp() public virtual override {
        super.setUp();
        vm.prank(PROXY_OWNER);
        rewarderFactory = new RewarderFactory(ORACLE);
        rewardManager = actors[7];
    }
}

contract TestInitialization is RewarderFactoryTest {
    function test_Init() public {
        assertEq(rewarderFactory.oracle(), ORACLE);
        assertNotEq(rewarderFactory.rewarderImplementation(), address(0));
    }
}

contract DeployRewarderTest is RewarderFactoryTest {
    Rewarder rewarder;

    function test_deployRewarder() public {
        vm.prank(rewardManager);
        vm.expectEmit(true, true, false, false, address(rewarderFactory)); // false, because rewarder address is unknown before calling the function
        emit IRewarderFactory.RewarderDeployed(SPA, rewardManager, rewardManager);
        rewarder = Rewarder(rewarderFactory.deployRewarder(SPA));
        assertNotEq(address(rewarder), address(0));
        assertEq(rewarder.REWARD_TOKEN(), SPA);
        assertEq(rewarder.rewarderFactory(), address(rewarderFactory));
    }
}

contract UpdateRewarderImplementationTest is RewarderFactoryTest {
    function test_revertWhen_CallerIsNotOwner() public {
        vm.prank(rewardManager);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rewardManager));
        rewarderFactory.updateRewarderImplementation(actors[3]);
    }

    function test_revertWhen_InvalidAddress() public {
        vm.prank(PROXY_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IRewarderFactory.InvalidAddress.selector));
        rewarderFactory.updateRewarderImplementation(address(0));
    }

    function test_updateRewarderImplementation() public {
        vm.prank(PROXY_OWNER);
        vm.expectEmit(address(rewarderFactory));
        emit IRewarderFactory.RewarderImplementationUpdated(actors[3]);
        rewarderFactory.updateRewarderImplementation(actors[3]);
        assertEq(rewarderFactory.rewarderImplementation(), actors[3]);
    }
}

contract UpdateOracleTest is RewarderFactoryTest {
    function test_revertWhen_CallerIsNotOwner() public {
        vm.prank(rewardManager);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rewardManager));
        rewarderFactory.updateOracle(actors[3]);
    }

    function test_revertWhen_InvalidAddress() public {
        vm.prank(PROXY_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IRewarderFactory.InvalidAddress.selector));
        rewarderFactory.updateOracle(address(0));
    }

    function test_updateOracle() public {
        vm.prank(PROXY_OWNER);
        vm.expectEmit(address(rewarderFactory));
        emit IRewarderFactory.OracleUpdated(actors[3]);
        rewarderFactory.updateOracle(actors[3]);
        assertEq(rewarderFactory.oracle(), actors[3]);
    }
}
