// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarmWithExpiry} from "../../contracts/features/BaseFarmWithExpiry.sol";
import {FarmFactory} from "../../contracts/FarmFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../BaseFarm.t.sol";

abstract contract BaseFarmWithExpiryTest is BaseFarmTest {
    uint256 public constant MIN_EXTENSION = 100; // in days
    uint256 public constant MAX_EXTENSION = 300; // in days

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
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
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
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
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
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
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
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else if (newStartTime < farmStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(lastFundUpdateTime, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
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

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - farmStartTime);
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

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - farmStartTime);
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

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTimeEight);
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

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTimeEight);
        assertEq(lastFundUpdateTime, newStartTimeEight);
    }
}

abstract contract ExtendFarmDurationTest is BaseFarmWithExpiryTest {
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
        vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
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
        vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
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
        vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
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
        vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
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
        BaseFarmWithExpiry(lockupFarm).getRewardBalance(rwdTokens[0]);
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
        BaseFarmWithExpiry(lockupFarm).getRewardBalance(rwdTokens[0]);
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
        BaseFarmWithExpiry(nonLockupFarm).getRewardBalance(rwdTokens[0]);
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
        BaseFarmWithExpiry(nonLockupFarm).getRewardBalance(rwdTokens[0]);
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

// Not testing expiry for other functions like ClaimRewards, AddRewards, SetRewardRate, etc. as it will be redundant.
// The above test cases are enough to cover the expiry logic and catch any changes in the expiry logic.
// We need to make sure we are not removing the farm active checks from the non-tested functions in the contracts.
// Even if we remove farm active checks by mistake, the tests in BaseFarm.t.sol will catch them due to its transient nature.
