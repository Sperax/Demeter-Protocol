// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/console.sol";
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
        address[] memory _baseTokens = new address[](2);
        _baseTokens[0] = DAI;
        _baseTokens[1] = USDCe;
        Rewarder.FarmRewardConfigInput memory _rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 1e9,
            maxRewardRate: type(uint256).max,
            baseTokens: _baseTokens,
            noLockupRewardPer: 5000
        });
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        changePrank(rewardManager);
        rewarder.updateRewardConfig(lockupFarm, _rewardConfig);
        deposit(lockupFarm, false, 1000);
        deal(USDCe, address(rewarder), 1e26);

        rewarder.calibrateReward(lockupFarm);
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
        _printStats();
    }

    function _printStats() private view {
        Rewarder.FarmRewardConfig memory _rwdConfig = rewarder.getFarmRewardConfig(lockupFarm);
        (address[] memory assets, uint256[] memory amounts) = CamelotV2Farm(lockupFarm).getTokenAmounts();
        uint256[] memory rwdRates = CamelotV2Farm(lockupFarm).getRewardRates(SPA);
        console.log("*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*");
        console.log("* Farm             : %s", lockupFarm);
        console.log("* Assets 0         : %s", assets[0]);
        console.log("* Assets 1         : %s", assets[1]);
        console.log("* BaseTokensLen    : %s", _rwdConfig.baseAssetIndexes.length);
        console.log("* BaseTokens 0     : %s", _rwdConfig.baseAssetIndexes[0]);
        console.log("* BaseTokens 1     : %s", _rwdConfig.baseAssetIndexes[1]);
        console.log("* APR              : %s", _rwdConfig.apr / 1e8, "%");
        console.log("*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*");
        console.log();
    }
}
