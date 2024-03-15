// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/console.sol";
import {CamelotV2FarmTest} from "../e721-farms/camelotV2/CamelotV2Farm.t.sol";
import {CamelotV2Farm} from "../../contracts/e721-farms/camelotV2/CamelotV2Farm.sol";
import {RewarderFactory} from "../../contracts/rewarder/RewarderFactory.sol";
import {Rewarder} from "../../contracts/rewarder/Rewarder.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";

contract RewarderTest is CamelotV2FarmTest {
    RewarderFactory public rewarderFactory;
    Rewarder public rewarder;
    address public constant ORACLE = 0x14D99412dAB1878dC01Fe7a1664cdE85896e8E50;
    address public rewardToken;
    address public rewardManager;
    address public farmAdmin;

    function setUp() public virtual override {
        super.setUp();
        rewardToken = USDCe;
        rewardManager = makeAddr("Reward manager");
        vm.prank(PROXY_OWNER);
        rewarderFactory = new RewarderFactory(ORACLE);
        vm.prank(rewardManager);
        rewarder = Rewarder(rewarderFactory.deployRewarder(rewardToken));
        deal(USDCe, address(rewarder), 1e26);
    }
}

contract TestInitialization is RewarderTest {
    function test_Init() public {
        assertEq(rewarder.rewarderFactory(), address(rewarderFactory));
        assertEq(rewarder.REWARD_TOKEN(), rewardToken);
        assertEq(rewarder.totalRewardRate(), 0);
        assertEq(rewarder.owner(), rewardManager);
    }
}

contract TestUpdateTokenManagerOfFarm is RewarderTest {
    function test_RevertsWhen_CallerIsNotTheOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        rewarder.updateTokenManagerOfFarm(lockupFarm, actors[1]);
    }

    function test_UpdateTokenManagerOfFarm() public {
        vm.prank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        vm.expectEmit(true, true, true, true, lockupFarm);
        emit RewardDataUpdated(rewardToken, actors[1]);
        vm.prank(rewardManager);
        rewarder.updateTokenManagerOfFarm(lockupFarm, actors[1]);
        (address tokenManager,,) = CamelotV2Farm(lockupFarm).rewardData(rewardToken);
        assertEq(tokenManager, actors[1]);
    }
}

contract TestUpdateAPR is RewarderTest {
    uint256 private constant APR = 1e9;

    function test_RevertWhen_updateAPR_CallerIsNotTheOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        rewarder.updateAPR(lockupFarm, APR);
    }

    function test_RevertWhen_updateAPR_NotConfigured() public useKnownActor(rewardManager) {
        vm.expectRevert(abi.encodeWithSelector(Rewarder.FarmNotConfigured.selector, lockupFarm));
        rewarder.updateAPR(lockupFarm, APR);
    }

    function test_UpdateAPR() public useKnownActor(rewardManager) {
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: UINT256_MAX,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 1000);
        rewarder.calibrateReward(lockupFarm);
        changePrank(rewardManager);
        rewarder.updateAPR(lockupFarm, 12e8);
        (uint256 apr, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertEq(apr, 12e8);
        assertTrue(rewardRate > 0);
        rewarder.updateAPR(lockupFarm, 0);
        (apr, rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertEq(apr, 0);
        assertEq(rewardRate, 0);
    }
}

contract TestUpdateRewardConfig is RewarderTest {
    Rewarder.FarmRewardConfigInput private rewardConfig;
    address[] private baseAssets;

    function setUp() public override {
        super.setUp();
        baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: UINT256_MAX,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
    }

    function test_RevertWhen_FarmDoesntHaveRewardToken() public useKnownActor(rewardManager) {
        Rewarder newRewarder = Rewarder(rewarderFactory.deployRewarder(SPA));
        vm.expectRevert(Rewarder.InvalidFarm.selector);
        newRewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_BaseTokenDoesNotExistInPoolToken() public useKnownActor(rewardManager) {
        baseAssets[0] = SPA;
        rewardConfig.baseTokens = baseAssets;
        vm.expectRevert(Rewarder.InvalidFarm.selector);
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_BaseTokenIsRepeated() public useKnownActor(rewardManager) {
        baseAssets = new address[](2);
        baseAssets[0] = DAI;
        baseAssets[1] = DAI;
        rewardConfig.baseTokens = baseAssets;
        vm.expectRevert(Rewarder.InvalidFarm.selector);
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_BaseTokensAreMoreThanAssets() public useKnownActor(rewardManager) {
        baseAssets = new address[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDCe;
        baseAssets[2] = DAI;
        rewardConfig.baseTokens = baseAssets;
        vm.expectRevert(Rewarder.InvalidFarm.selector);
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_BaseAssetPriceFeedDoesntExist() public useKnownActor(rewardManager) {
        vm.mockCall(ORACLE, abi.encodeWithSelector(IOracle.priceFeedExists.selector, USDCe), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(Rewarder.PriceFeedDoesNotExist.selector, USDCe));
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_NonLockupRewardPer0() public useKnownActor(rewardManager) {
        rewardConfig.nonLockupRewardPer = 0;
        vm.expectRevert(abi.encodeWithSelector(Rewarder.InvalidRewardPercentage.selector, 0));
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_RevertWhen_NonLockupRewardPerMoreThanMax() public useKnownActor(rewardManager) {
        rewardConfig.nonLockupRewardPer = 10001;
        vm.expectRevert(abi.encodeWithSelector(Rewarder.InvalidRewardPercentage.selector, 10001));
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
    }

    function test_UpdateRewardToken_BaseTokensHaveBothPoolAssets() public useKnownActor(rewardManager) {
        baseAssets = new address[](2);
        baseAssets[0] = DAI;
        baseAssets[1] = USDCe;
        rewardConfig.baseTokens = baseAssets;
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        _assertRewardConfig(rewardConfig);
    }

    function test_UpdateRewardToken() public useKnownActor(rewardManager) {
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        _assertRewardConfig(rewardConfig);
    }

    function _assertRewardConfig(Rewarder.FarmRewardConfigInput memory intendedRwdConfig) public {
        (uint256 apr, uint256 rewardRate, uint256 maxRewardRate, uint256 nonLockupRewardPer) =
            rewarder.farmRewardConfigs(lockupFarm);
        assertEq(apr, intendedRwdConfig.apr);
        assertEq(rewardRate, 0);
        assertEq(maxRewardRate, intendedRwdConfig.maxRewardRate);
        assertEq(nonLockupRewardPer, intendedRwdConfig.nonLockupRewardPer);
    }
}

contract TestFlow is RewarderTest {
    function test_temp() public {
        address[] memory _baseTokens = new address[](2);
        _baseTokens[0] = DAI;
        _baseTokens[1] = USDCe;
        Rewarder.FarmRewardConfigInput memory _rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 1e9,
            maxRewardRate: type(uint256).max,
            baseTokens: _baseTokens,
            nonLockupRewardPer: 5000
        });
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        changePrank(rewardManager);
        rewarder.updateRewardConfig(lockupFarm, _rewardConfig);
        deposit(lockupFarm, false, 1000);
        rewarder.calibrateReward(lockupFarm);

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
        (address[] memory assets,) = CamelotV2Farm(lockupFarm).getTokenAmounts();
        // uint256[] memory rwdRates = CamelotV2Farm(lockupFarm).getRewardRates(SPA);
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
