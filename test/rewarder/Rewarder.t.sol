// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CamelotV2FarmTest} from "../e721-farms/camelotV2/CamelotV2Farm.t.sol";
import {CamelotV2Farm} from "../../contracts/e721-farms/camelotV2/CamelotV2Farm.sol";
import {RewarderFactory} from "../../contracts/rewarder/RewarderFactory.sol";
import {Rewarder, IERC20, ERC20} from "../../contracts/rewarder/Rewarder.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {Farm} from "./../../contracts/Farm.sol";

contract RewarderTest is CamelotV2FarmTest {
    RewarderFactory public rewarderFactory;
    Rewarder public rewarder;
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
    function test_RevertWhen_CallerIsNotTheOwner() public useKnownActor(actors[5]) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actors[5]));
        rewarder.updateTokenManagerOfFarm(lockupFarm, actors[1]);
    }

    function test_UpdateTokenManagerOfFarm() public {
        vm.prank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        vm.expectEmit(true, true, true, true, lockupFarm);
        emit Farm.RewardDataUpdated(rewardToken, actors[1]);
        vm.prank(rewardManager);
        rewarder.updateTokenManagerOfFarm(lockupFarm, actors[1]);
        (address tokenManager,,) = CamelotV2Farm(lockupFarm).rewardData(rewardToken);
        assertEq(tokenManager, actors[1]);
    }
}

contract TestRecoverRewardFundsOfFarm is RewarderTest {
    uint256 public amount;

    function test_RevertWhen_CallerIsNotTheOwner() public useKnownActor(actors[5]) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actors[5]));
        rewarder.recoverRewardFundsOfFarm(lockupFarm, amount);
    }

    function test_recoverRewardFundsOfFarm() public {
        vm.prank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        uint256 balanceBefore = IERC20(USDCe).balanceOf(address(rewarder));
        amount = 100 * 10 ** ERC20(USDCe).decimals();
        deal(USDCe, lockupFarm, amount);
        vm.expectEmit(true, true, true, true, lockupFarm);
        emit Farm.FundsRecovered(address(rewarder), USDCe, amount);
        vm.prank(rewardManager);
        rewarder.recoverRewardFundsOfFarm(lockupFarm, amount);
        uint256 balanceAfter = IERC20(USDCe).balanceOf(address(rewarder));
        assertEq(balanceAfter - balanceBefore, amount);
    }
}

contract TestUpdateAPR is RewarderTest {
    uint256 private APR;

    function test_RevertWhen_updateAPR_CallerIsNotTheOwner() public useKnownActor(actors[5]) {
        APR = 1e9;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actors[5]));
        rewarder.updateAPR(lockupFarm, APR);
    }

    function test_RevertWhen_updateAPR_NotConfigured() public useKnownActor(rewardManager) {
        APR = 1e9;
        vm.expectRevert(abi.encodeWithSelector(Rewarder.FarmNotConfigured.selector, lockupFarm));
        rewarder.updateAPR(lockupFarm, APR);
    }

    function test_UpdateAPR() public useKnownActor(rewardManager) {
        _setupFarmRewards();
        rewarder.calibrateReward(lockupFarm);
        APR = 12e8;
        changePrank(rewardManager);
        rewarder.updateAPR(lockupFarm, APR);
        (uint256 apr, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertEq(apr, APR);
        assertTrue(rewardRate > 0);
        rewarder.updateAPR(lockupFarm, 0);
        (apr, rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertEq(apr, 0);
        assertEq(rewardRate, 0);
    }

    function test_UpdateAPR_CapRewardsWithBalance() public useKnownActor(rewardManager) {
        _setupFarmRewards();
        changePrank(address(rewarder));
        IERC20(USDCe).transfer(
            actors[1], IERC20(USDCe).balanceOf(address(rewarder)) - 1 * 10 ** ERC20(USDCe).decimals()
        );
        uint256 rewardsSent = rewarder.calibrateReward(lockupFarm);
        assertEq(rewardsSent, 1 * 10 ** ERC20(USDCe).decimals());
    }

    function test_UpdateAPR_CapRewardsWithMaxRwdRate() public useKnownActor(rewardManager) {
        uint128 MAX_REWARD_RATE = 50; // 50 wei: Because rwdToken decimals are 6
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: MAX_REWARD_RATE,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 100000);
        rewarder.calibrateReward(lockupFarm);
        (, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertEq(rewardRate, MAX_REWARD_RATE);
    }

    function test_UpdateAPR_ForBaseTokenDecimalsMoreThanRwdTokenDecimals() public useKnownActor(rewardManager) {
        rewarder = Rewarder(rewarderFactory.deployRewarder(USDCe));
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = DAI;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 12e8,
            maxRewardRate: type(uint128).max,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 1000);
        rewarder.calibrateReward(lockupFarm);
        (, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertTrue((rewardRate * 30 days) / 1e6 > 0);
        assertEq((rewardRate * 30 days) / 1e9, 0);
    }

    function test_UpdateAPR_ForRwdTokenDecimalsMoreThanBaseTokenDecimals() public useKnownActor(rewardManager) {
        vm.mockCall(USDCe, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(20));
        rewarder = Rewarder(rewarderFactory.deployRewarder(USDCe));
        vm.clearMockedCalls();
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = DAI;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 12e8,
            maxRewardRate: type(uint128).max,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 1000);
        rewarder.calibrateReward(lockupFarm);
        (, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        assertTrue((rewardRate * 30 days) / 1e20 > 0);
    }

    function _setupFarmRewards() private {
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: type(uint128).max,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 1000);
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
            maxRewardRate: type(uint128).max,
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

contract TestRecoverERC20 is RewarderTest {
    uint256 constant RECOVERY_AMOUNT = 1e21;
    address constant RECOVERY_TOKEN = USDT; // Aave arb LUSD

    function test_RevertWhen_CallerIsNotOwner() public useActor(5) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actors[5]));
        rewarder.recoverERC20(RECOVERY_TOKEN, RECOVERY_AMOUNT);
    }

    function test_RevertWhen_ZeroAmount() public useKnownActor(rewardManager) {
        vm.expectRevert(abi.encodeWithSelector(Rewarder.ZeroAmount.selector));
        rewarder.recoverERC20(RECOVERY_TOKEN, RECOVERY_AMOUNT);
    }

    function test_RecoverERC20() public useKnownActor(rewardManager) {
        deal(RECOVERY_TOKEN, address(rewarder), RECOVERY_AMOUNT);
        uint256 balBefore = IERC20(RECOVERY_TOKEN).balanceOf(rewardManager);
        rewarder.recoverERC20(RECOVERY_TOKEN, RECOVERY_AMOUNT);
        uint256 balAfter = IERC20(RECOVERY_TOKEN).balanceOf(rewardManager);
        assertEq(balAfter - balBefore, RECOVERY_AMOUNT);
    }
}

contract TestCalibrationRestriction is RewarderTest {
    function setUp() public override {
        super.setUp();
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: type(uint128).max,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        vm.prank(rewardManager);
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        vm.prank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
    }

    function test_RevertWhen_CallerIsNotOwner() public useActor(5) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actors[5]));
        rewarder.toggleCalibrationRestriction(lockupFarm);
    }

    function test_ToggleCalibrationRestriction() public {
        vm.prank(rewardManager);
        rewarder.toggleCalibrationRestriction(lockupFarm);
        vm.expectRevert(abi.encodeWithSelector(Rewarder.CalibrationRestricted.selector, lockupFarm));
        rewarder.calibrateReward(lockupFarm);
    }

    function test_ToggleCalibrationRestriction_CalibrateWhenCalledByOwner() public useKnownActor(rewardManager) {
        rewarder.toggleCalibrationRestriction(lockupFarm);
        // This should not revert
        rewarder.calibrateReward(lockupFarm);
    }

    function test_ToggleCalibrationRestriction_RemoveRestriction() public {
        vm.prank(rewardManager);
        rewarder.toggleCalibrationRestriction(lockupFarm);
        vm.prank(rewardManager);
        rewarder.toggleCalibrationRestriction(lockupFarm);
        rewarder.calibrateReward(lockupFarm);
    }
}

contract GetTokenAmountsTest is RewarderTest {
    function test_getTokenAmounts() public depositSetup(lockupFarm, true) {
        (address[] memory tokens, uint256[] memory amounts) = rewarder.getTokenAmounts(lockupFarm);
        (address[] memory expectedTokens, uint256[] memory expectedAmounts) =
            CamelotV2Farm(lockupFarm).getTokenAmounts();
        for (uint8 i; i < tokens.length; ++i) {
            assertEq(tokens[i], expectedTokens[i]);
            assertEq(amounts[i], expectedAmounts[i]);
        }
    }
}

contract TestRewardsEndTime is RewarderTest {
    function test_rewardsEndTime() public depositSetup(lockupFarm, true) useKnownActor(rewardManager) {
        Rewarder.FarmRewardConfigInput memory rewardConfig;
        address[] memory baseAssets = new address[](1);
        baseAssets[0] = USDCe;
        rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 5e9,
            maxRewardRate: type(uint128).max,
            baseTokens: baseAssets,
            nonLockupRewardPer: 5000
        });
        rewarder.updateRewardConfig(lockupFarm, rewardConfig);
        changePrank(owner);
        CamelotV2Farm(lockupFarm).updateRewardData(USDCe, address(rewarder));
        deposit(lockupFarm, false, 1000);
        rewarder.calibrateReward(lockupFarm);
        assertTrue(rewarder.totalRewardRate() > 0);
        uint256 rewardsEndTime = rewarder.rewardsEndTime(lockupFarm);
        uint256 farmBalance = IERC20(USDCe).balanceOf(lockupFarm);
        (, uint256 rewardRate,,) = rewarder.farmRewardConfigs(lockupFarm);
        uint256 expectedRewardsEndTime = block.timestamp
            + ((farmBalance / rewardRate) + (IERC20(USDCe).balanceOf(address(rewarder)) / rewarder.totalRewardRate()));
        assertEq(rewardsEndTime, expectedRewardsEndTime);
    }
}

contract TestFlow is RewarderTest {
    function test_temp() public {
        address[] memory _baseTokens = new address[](2);
        _baseTokens[0] = DAI;
        _baseTokens[1] = USDCe;
        Rewarder.FarmRewardConfigInput memory _rewardConfig = Rewarder.FarmRewardConfigInput({
            apr: 1e9,
            maxRewardRate: type(uint128).max,
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
