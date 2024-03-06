// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {CamelotV2FarmTest} from "../e721-farms/camelotV2/CamelotV2Farm.t.sol";
import {CamelotV2Farm} from "../../contracts/e721-farms/camelotV2/CamelotV2Farm.sol";
import {RewarderFactory} from "../../contracts/rewarder/RewarderFactory.sol";
import {Rewarder} from "../../contracts/rewarder/Rewarder.sol";

contract RewarderTest is CamelotV2FarmTest {
    RewarderFactory public rewarderFactory;
    Rewarder public rewarder;
    address public constant ORACLE = 0x14D99412dAB1878dC01Fe7a1664cdE85896e8E50;
    address public rewardManager;
    address public farmAdmin;

    function setUp() public override {
        super.setUp();
        rewardManager = makeAddr("Reward manager");
        vm.prank(PROXY_OWNER);
        rewarderFactory = new RewarderFactory(ORACLE);
        vm.startPrank(rewardManager);
        rewarder = Rewarder(rewarderFactory.deployRewarder(USDCe));
        address[] memory _baseTokens = new address[](1);
        _baseTokens[0] = DAI;
        Rewarder.FarmRewardConfig memory _rewardConfig = Rewarder.FarmRewardConfig({
            apr: 1e9,
            rewardRate: 0,
            maxRewardRate: type(uint256).max,
            baseTokens: _baseTokens,
            noLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, _rewardConfig);
        deposit(lockupFarm, false, 1000);
        deal(USDCe, address(rewarder), 1e26);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        rewarder.calibrateRewards(lockupFarm);
    }

    function test_Init() public {
        (uint256 apr, uint256 rewardsPerSec, uint256 maxRewardRate,) = rewarder.farmRewardConfigs(lockupFarm);
        uint256 globalRewardsPerSec = rewarder.totalRewardRate();
        emit log_named_uint("APR", apr);
        emit log_named_uint("RPS (Rewards per sec)", rewardsPerSec);
        emit log_named_uint("Max RPS", maxRewardRate);
        emit log_named_uint("Global RPS", globalRewardsPerSec);
        assertTrue(rewardsPerSec > 0);
        assertTrue(globalRewardsPerSec > 0);
    }
}
