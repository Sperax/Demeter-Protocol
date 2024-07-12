// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {CamelotV3Farm} from "../../contracts/e721-farms/camelotV3/CamelotV3Farm.sol";
import {RewarderFactory} from "./../../contracts/rewarder/RewarderFactory.sol";
import {TestNetworkConfig} from "../utils/TestNetworkConfig.t.sol";
import {IRewarder, Rewarder} from "./../../contracts/rewarder/Rewarder.sol";

contract RewarderBugSimulation is TestNetworkConfig {
    CamelotV3Farm public farm;
    RewarderFactory public rewarderFactory;
    Rewarder public rewarder;

    function setUp() public override {
        super.setUp();
        farm = CamelotV3Farm(0xeCC7DCF862bFE601670413139926E01e6eEd2323);
        vm.startPrank(0x12DBb60bAd909e6d9139aBd61D0c9AA11eB49D51);
    }

    function test_deployedRewarder() external {
        rewarder = Rewarder(0x3529D51de1c473cD78D439784825f40738f001FD);
        _commonActions();
    }

    function test_fixedRewarder() external {
        rewarderFactory = new RewarderFactory(ORACLE);
        rewarder = Rewarder(rewarderFactory.deployRewarder(SPA));
        _commonActions();
    }

    function _commonActions() internal {
        address[] memory baseAssets = new address[](2);
        baseAssets[0] = USDS;
        baseAssets[1] = SPA;
        IRewarder.FarmRewardConfigInput memory rewardConfig = IRewarder.FarmRewardConfigInput({
            apr: 1e9,
            maxRewardRate: 390239423,
            baseTokens: baseAssets,
            nonLockupRewardPer: 1e4
        });
        rewarder.updateRewardConfig(address(farm), rewardConfig);
        rewarder.updateRewardConfig(address(farm), rewardConfig);
        baseAssets = new address[](1);
        baseAssets[0] = SPA;
        rewardConfig = IRewarder.FarmRewardConfigInput({
            apr: 1e9,
            maxRewardRate: 390239423,
            baseTokens: baseAssets,
            nonLockupRewardPer: 1e4
        });
        rewarder.updateRewardConfig(address(farm), rewardConfig);
        IRewarder.FarmRewardConfig memory _rewardConfig = rewarder.getFarmRewardConfig(address(farm));
        uint256[] memory baseAssetsIndexes = _rewardConfig.baseAssetIndexes;
        for (uint8 i; i < baseAssetsIndexes.length; i++) {
            console.logUint(baseAssetsIndexes[i]);
        }
    }
}
