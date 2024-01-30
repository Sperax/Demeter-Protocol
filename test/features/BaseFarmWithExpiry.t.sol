// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarmWithExpiry} from "../../contracts/features/BaseFarmWithExpiry.sol";
import {FarmFactory} from "../../contracts/FarmFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../BaseFarm.t.sol";

abstract contract BaseFarmWithExpiryTest is
    UpdateFarmStartTimeTest,
    WithdrawTest,
    ClaimRewardsTest,
    AddRewardsTest,
    SetRewardRateTest,
    UpdateRewardTokenDataTest,
    FarmPauseSwitchTest,
    UpdateCoolDownPeriodTest,
    CloseFarmTest
{
    event FarmEndTimeUpdated(uint256 newEndTime);
    event ExtensionFeeCollected(address token, uint256 extensionFee);
}

abstract contract UpdateFarmStartTimeWithExpiryTest is BaseFarmWithExpiryTest {
    function test_updateFarmStartTime_nonLockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_updateFarmStartTime_lockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_updateFarmStartTimeWithExpiry_noLockupFarm(uint256 farmStartTime, uint256 newStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, farmStartTime - 1, type(uint64).max);
        address farm = createFarm(farmStartTime, false);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        } else {
            timeDelta = 0;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        if (newStartTime > farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        }
    }

    function test_updateFarmStartTimeWithExpiry_lockupFarm(uint256 farmStartTime, uint256 newStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, farmStartTime - 1, type(uint64).max);

        address farm = createFarm(farmStartTime, true);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        } else {
            timeDelta = 0;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        if (newStartTime > farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        }
    }

    // the above fuzz test contains very low range for newStartTime on the negative delta side and further it there is a chance it can miss the no delta case.
    // so wrote the below tests.

    function test_updateFarmStartTime_lockupFarm_end_time_withDelta(uint256 newStartTime) public {
        uint256 farmStartTime = block.timestamp + 50 days;
        newStartTime = bound(newStartTime, block.timestamp, type(uint64).max);

        address farm = createFarm(farmStartTime, true);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        } else {
            timeDelta = 0;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);

        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        if (newStartTime > farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        }
    }

    function test_updateFarmStartTime_noLockupFarm_end_time_withDelta(uint256 newStartTime) public {
        uint256 farmStartTime = block.timestamp + 50 days;
        newStartTime = bound(newStartTime, block.timestamp, type(uint64).max);

        address farm = createFarm(farmStartTime, false);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        } else {
            timeDelta = 0;
        }

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        if (newStartTime > farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(100 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        }
    }

    function test_updateFarmStartTime_lockupFarm_end_time_noDelta(uint256 farmStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);

        address farm = createFarm(farmStartTime, true);

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(farmStartTime);
        BaseFarmWithExpiry(farm).updateFarmStartTime(farmStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        assertEq(100 days, farmEndTimeAfterUpdate - farmStartTime);
        assertEq(lastFundUpdateTime, farmStartTime);
    }

    function test_updateFarmStartTime_noLockupFarm_end_time_noDelta(uint256 farmStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);

        address farm = createFarm(farmStartTime, false);

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(farmStartTime);
        BaseFarmWithExpiry(farm).updateFarmStartTime(farmStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        assertEq(100 days, farmEndTimeAfterUpdate - farmStartTime);
        assertEq(lastFundUpdateTime, farmStartTime);
    }

    function test_updateFarmStartTime_lockupFarm_end_time_withDelta_multiUpdate() public {
        uint256 farmStartTime = block.timestamp + 50 days;
        uint256 newStartTimeOne = block.timestamp + 70 days;
        uint256 newStartTimeTwo = block.timestamp + 90 days;
        uint256 newStartTimeThree = block.timestamp + 60 days;
        uint256 newStartTimeFour = block.timestamp + 65 days;
        uint256 newStartTimeFive = block.timestamp + 40 days;
        uint256 newStartTimeSix = block.timestamp + 20 days;
        uint256 newStartTimeSeven = block.timestamp + 30 days;
        uint256 newStartTimeEight = block.timestamp + 35 days;

        address farm = createFarm(farmStartTime, true);

        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeOne);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeTwo);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeThree);
        vm.warp(block.timestamp + 1 days);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeFour);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeFive);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeSix);
        vm.warp(block.timestamp + 2 days);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeSeven);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeEight);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        assertEq(100 days, farmEndTimeAfterUpdate - newStartTimeEight);
        assertEq(lastFundUpdateTime, newStartTimeEight);
    }

    function test_updateFarmStartTime_noLockupFarm_end_time_withDelta_multiUpdate() public {
        uint256 farmStartTime = block.timestamp + 50 days;
        uint256 newStartTimeOne = block.timestamp + 70 days;
        uint256 newStartTimeTwo = block.timestamp + 90 days;
        uint256 newStartTimeThree = block.timestamp + 60 days;
        uint256 newStartTimeFour = block.timestamp + 65 days;
        uint256 newStartTimeFive = block.timestamp + 40 days;
        uint256 newStartTimeSix = block.timestamp + 20 days;
        uint256 newStartTimeSeven = block.timestamp + 30 days;
        uint256 newStartTimeEight = block.timestamp + 35 days;

        address farm = createFarm(farmStartTime, false);

        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeOne);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeTwo);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeThree);
        vm.warp(block.timestamp + 1 days);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeFour);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeFive);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeSix);
        vm.warp(block.timestamp + 2 days);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeSeven);
        BaseFarmWithExpiry(farm).updateFarmStartTime(newStartTimeEight);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        uint256 lastFundUpdateTime = BaseFarmWithExpiry(farm).lastFundUpdateTime();

        assertEq(100 days, farmEndTimeAfterUpdate - newStartTimeEight);
        assertEq(lastFundUpdateTime, newStartTimeEight);
    }
}

abstract contract ExtendFarmDurationWithExpiryTest is BaseFarmWithExpiryTest {
    function test_extendFarmDuration_noLockupFarm_revertsWhen_FarmNotYetStarted() public {
        uint256 extensionDays = 200;
        uint256 farmStartTime = block.timestamp + 50 days;
        address farm = createFarm(farmStartTime, false);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmNotYetStarted.selector));
        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_extendFarmDuration_lockupFarm_revertsWhen_FarmNotYetStarted() public {
        uint256 extensionDays = 200;
        uint256 farmStartTime = block.timestamp + 50 days;
        address farm = createFarm(farmStartTime, true);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmNotYetStarted.selector));
        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_extendFarmDuration_noLockupFarm_revertsWhen_InvalidExtension() public useKnownActor(owner) {
        uint256 extensionDays = 99;
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.InvalidExtension.selector));
        BaseFarmWithExpiry(nonLockupFarm).extendFarmDuration(extensionDays);
        extensionDays = 301;
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.InvalidExtension.selector));
        BaseFarmWithExpiry(nonLockupFarm).extendFarmDuration(extensionDays);
    }

    function test_extendFarmDuration_lockupFarm_revertsWhen_InvalidExtension() public useKnownActor(owner) {
        uint256 extensionDays = 99;
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.InvalidExtension.selector));
        BaseFarmWithExpiry(lockupFarm).extendFarmDuration(extensionDays);
        extensionDays = 301;
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.InvalidExtension.selector));
        BaseFarmWithExpiry(lockupFarm).extendFarmDuration(extensionDays);
    }

    function test_extendFarmDuration_noLockupFarm_revertsWhen_farmClosed() public useKnownActor(owner) {
        uint256 extensionDays = 200;
        BaseFarmWithExpiry(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarmWithExpiry(nonLockupFarm).extendFarmDuration(extensionDays);
    }

    function test_extendFarmDuration_lockupFarm_revertsWhen_farmClosed() public useKnownActor(owner) {
        uint256 extensionDays = 200;
        BaseFarmWithExpiry(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarmWithExpiry(lockupFarm).extendFarmDuration(extensionDays);
    }

    function test_extendFarmDuration_noLockupFarm_revertsWhen_farmExpired(uint256 extensionDays, uint256 farmStartTime)
        public
    {
        vm.assume(extensionDays >= 100 && extensionDays <= 300);
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, false);
        uint256 farmEndTime = BaseFarmWithExpiry(farm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_extendFarmDuration_lockupFarm_revertsWhen_farExpired(uint256 extensionDays, uint256 farmStartTime)
        public
    {
        vm.assume(extensionDays >= 100 && extensionDays <= 300);
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, true);
        uint256 farmEndTime = BaseFarmWithExpiry(farm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        vm.startPrank(owner);
        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_extendFarmDuration_noLockupFarm(uint256 extensionDays, uint256 farmStartTime) public {
        vm.assume(extensionDays >= 100 && extensionDays <= 300);
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, false);
        vm.warp(farmStartTime + 1);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();

        uint256 extensionFeePerDay = FarmFactory(DEMETER_FACTORY).extensionFeePerDay();
        address feeReceiver = FarmFactory(DEMETER_FACTORY).feeReceiver();
        address feeToken = FarmFactory(DEMETER_FACTORY).feeToken();
        uint256 extensionFeeAmount = extensionDays * extensionFeePerDay;

        uint256 feeReceiverTokenBalanceBeforeExtension = IERC20(feeToken).balanceOf(feeReceiver);

        vm.startPrank(owner);
        IERC20(feeToken).approve(farm, 500 * 1e20);

        if (extensionFeePerDay != 0) {
            vm.expectEmit(true, false, false, true);
            emit ExtensionFeeCollected(feeToken, extensionFeeAmount);
        }
        vm.expectEmit(true, false, false, true);
        emit FarmEndTimeUpdated(farmEndTimeBeforeUpdate + extensionDays * 1 days);

        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        vm.stopPrank();

        uint256 feeReceiverTokenBalanceAfterExtension = IERC20(feeToken).balanceOf(feeReceiver);

        assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + extensionDays * 1 days);
        assertTrue(feeReceiverTokenBalanceAfterExtension > feeReceiverTokenBalanceBeforeExtension);
        assertEq(feeReceiverTokenBalanceAfterExtension, feeReceiverTokenBalanceBeforeExtension + extensionFeeAmount);
    }

    function test_extendFarmDuration_lockupFarm(uint256 extensionDays, uint256 farmStartTime) public {
        vm.assume(extensionDays >= 100 && extensionDays <= 300);
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, true);
        vm.warp(farmStartTime + 1);
        uint256 farmEndTimeBeforeUpdate = BaseFarmWithExpiry(farm).farmEndTime();

        uint256 extensionFeePerDay = FarmFactory(DEMETER_FACTORY).extensionFeePerDay();
        address feeReceiver = FarmFactory(DEMETER_FACTORY).feeReceiver();
        address feeToken = FarmFactory(DEMETER_FACTORY).feeToken();
        uint256 extensionFeeAmount = extensionDays * extensionFeePerDay;

        uint256 feeReceiverTokenBalanceBeforeExtension = IERC20(feeToken).balanceOf(feeReceiver);

        vm.startPrank(owner);
        IERC20(feeToken).approve(farm, 500 * 1e20);

        if (extensionFeePerDay != 0) {
            vm.expectEmit(true, false, false, true);
            emit ExtensionFeeCollected(feeToken, extensionFeeAmount);
        }
        vm.expectEmit(true, false, false, true);
        emit FarmEndTimeUpdated(farmEndTimeBeforeUpdate + extensionDays * 1 days);

        BaseFarmWithExpiry(farm).extendFarmDuration(extensionDays);
        uint256 farmEndTimeAfterUpdate = BaseFarmWithExpiry(farm).farmEndTime();
        vm.stopPrank();

        uint256 feeReceiverTokenBalanceAfterExtension = IERC20(feeToken).balanceOf(feeReceiver);

        assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + extensionDays * 1 days);
        assertTrue(feeReceiverTokenBalanceAfterExtension > feeReceiverTokenBalanceBeforeExtension);
        assertEq(feeReceiverTokenBalanceAfterExtension, feeReceiverTokenBalanceBeforeExtension + extensionFeeAmount);
    }
}

abstract contract WithdrawWithExpiryTest is BaseFarmWithExpiryTest {
    function test_withdraw_lockupFarm_notClosedButExpired() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        BaseFarmWithExpiry(lockupFarm).getRewardBalance(SPA);
        vm.warp(BaseFarmWithExpiry(lockupFarm).farmEndTime() + 1);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarmWithExpiry(lockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(lockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarmWithExpiry(lockupFarm).withdraw(depositId);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_lockupFarm_closedAndExpired() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        BaseFarmWithExpiry(lockupFarm).getRewardBalance(SPA);
        vm.warp(BaseFarmWithExpiry(lockupFarm).farmEndTime() - 100);
        vm.startPrank(owner);
        BaseFarmWithExpiry(lockupFarm).closeFarm(); // if farm is closed it is also paused
        vm.warp(BaseFarmWithExpiry(lockupFarm).farmEndTime() + 1);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarmWithExpiry(lockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(lockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarmWithExpiry(lockupFarm).withdraw(depositId);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarmWithExpiry(lockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_nonLockupFarm_notClosedButExpired() public depositSetup(nonLockupFarm, false) {
        uint256 depositId = 1;
        BaseFarmWithExpiry(nonLockupFarm).getRewardBalance(SPA);
        vm.warp(BaseFarmWithExpiry(nonLockupFarm).farmEndTime() + 1);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarmWithExpiry(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(nonLockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarmWithExpiry(nonLockupFarm).withdraw(depositId);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_nonLockupFarm_closedAndExpired()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        BaseFarmWithExpiry(nonLockupFarm).getRewardBalance(SPA);
        vm.warp(BaseFarmWithExpiry(nonLockupFarm).farmEndTime() - 100);
        vm.startPrank(owner);
        BaseFarmWithExpiry(nonLockupFarm).closeFarm(); // if farm is closed it is also paused
        vm.warp(BaseFarmWithExpiry(nonLockupFarm).farmEndTime() + 1);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarmWithExpiry(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(nonLockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarmWithExpiry(nonLockupFarm).withdraw(depositId);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarmWithExpiry(nonLockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }
}

abstract contract ClaimRewardsWithExpiryTest is BaseFarmWithExpiryTest {
    function test_claimRewards_lockupFarm_revertsWhen_farmHasExpired()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).claimRewards(0);
    }

    function test_claimRewards_nonLockupFarm_revertsWhen_farmHasExpired()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).claimRewards(0);
    }
}

abstract contract AddRewardsWithExpiryTest is BaseFarmWithExpiryTest {
    function test_addRewards_lockupFarm_revertsWhen_farmHasExpired()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        uint256 rwdAmt = 1000 * 10 ** ERC20(rewardTokens[0]).decimals();
        deal(address(rewardTokens[0]), currentActor, rwdAmt);
        ERC20(rewardTokens[0]).approve(lockupFarm, rwdAmt);
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).addRewards(rewardTokens[0], rwdAmt);
    }

    function test_addRewards_nonLockupFarm_revertsWhen_farmHasExpired()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        uint256 rwdAmt = 1000 * 10 ** ERC20(rewardTokens[0]).decimals();
        deal(address(rewardTokens[0]), currentActor, rwdAmt);
        ERC20(rewardTokens[0]).approve(nonLockupFarm, rwdAmt);
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).addRewards(rewardTokens[0], rwdAmt);
    }
}

abstract contract SetRewardRateWithExpiryTest is BaseFarmWithExpiryTest {
    function testFuzz_setRewardRate_nonLockupFarm_revertsWhen_farmHasExpired(uint256 rwdRateNonLockup)
        public
        useKnownActor(owner)
    {
        uint256[] memory rwdRate = new uint256[](1);
        rwdRate[0] = rwdRateNonLockup;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarmWithExpiry(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
        }
        vm.warp(BaseFarmWithExpiry(nonLockupFarm).farmEndTime() + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).setRewardRate(rewardTokens[0], rwdRate);
    }

    function testFuzz_setRewardRate_lockupFarm_revertsWhen_farmHasExpired(
        uint256 rwdRateNonLockup,
        uint256 rwdRateLockup
    ) public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](2);
        rwdRate[0] = rwdRateNonLockup;
        rwdRate[1] = rwdRateLockup;
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        uint256[] memory oldRewardRate = new uint256[](2);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarmWithExpiry(lockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            rwdRateLockup = bound(
                rwdRateLockup, 2 * 10 ** ERC20(rewardTokens[i]).decimals(), 4 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
        }
        vm.warp(BaseFarmWithExpiry(lockupFarm).farmEndTime() + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).setRewardRate(rewardTokens[0], rwdRate);
    }
}

abstract contract UpdateRewardTokenDataWithExpiryTest is BaseFarmWithExpiryTest {
    function test_updateTknManager_nonLockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager_LockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        address _newTknManager = newTokenManager;
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }
}

abstract contract FarmPauseSwitchWithExpiryTest is BaseFarmWithExpiryTest {
    function test_farmPause_noLockupFarm_revertsWhen_FarmHasExpired(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarmWithExpiry(nonLockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_lockupFarm_revertsWhen_FarmHasExpired(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarmWithExpiry(lockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).farmPauseSwitch(_isPaused);
    }
}

abstract contract UpdateCoolDownPeriodWithExpiryTest is BaseFarmWithExpiryTest {
    function test_updateCoolDown_noLockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 cooldownPeriod = 15;
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_updateCoolDown_lockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 cooldownPeriod = 15;
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }
}

abstract contract CloseFarmWithExpiryTest is BaseFarmTest {
    function test_closeFarm_noLockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = BaseFarmWithExpiry(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(nonLockupFarm).closeFarm();
    }

    function test_closeFarm_lockupFarm_revertsWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = BaseFarmWithExpiry(lockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarmWithExpiry.FarmHasExpired.selector));
        BaseFarmWithExpiry(lockupFarm).closeFarm();
    }
}
