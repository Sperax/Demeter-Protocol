// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ExpirableFarm} from "../../contracts/features/ExpirableFarm.sol";
import {FarmRegistry} from "../../contracts/FarmRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Farm.t.sol";

abstract contract ExpirableFarmTest is FarmTest {
    uint256 public constant MIN_EXTENSION = 100; // in days
    uint256 public constant MAX_EXTENSION = 300; // in days

    event FarmEndTimeUpdated(uint256 newEndTime);
    event ExtensionFeeCollected(address token, uint256 extensionFee);
}

abstract contract UpdateFarmStartTimeWithExpiryTest is ExpirableFarmTest {
    function _assertHelper(
        uint256 initialStartTime,
        uint256 farmEndTimeBeforeUpdate,
        uint256 farmEndTimeAfterUpdate,
        uint256 farmStartTimeAfterUpdate,
        uint256 newStartTime,
        uint256 timeDelta,
        uint256 lastFundUpdateTime
    ) internal {
        if (newStartTime > initialStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(farmStartTimeAfterUpdate, newStartTime);
        } else if (newStartTime < initialStartTime) {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate - timeDelta);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(farmStartTimeAfterUpdate, newStartTime);
        } else {
            assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate);
            assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
            assertEq(farmStartTimeAfterUpdate, newStartTime);
        }

        assertEq(lastFundUpdateTime, 0);
    }

    function test_updateFarmStartTime_RevertWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = ExpirableFarm(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        ExpirableFarm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function testFuzz_updateFarmStartTimeWithExpiry(bool lockup, uint256 initialStartTime, uint256 newStartTime)
        public
    {
        initialStartTime = bound(initialStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, initialStartTime - 1, type(uint64).max);
        address farm = createFarm(initialStartTime, lockup);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > initialStartTime) {
            timeDelta = newStartTime - initialStartTime;
        } else if (newStartTime < initialStartTime) {
            timeDelta = initialStartTime - newStartTime;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 farmStartTimeAfterUpdate = ExpirableFarm(farm).farmStartTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        _assertHelper(
            initialStartTime,
            farmEndTimeBeforeUpdate,
            farmEndTimeAfterUpdate,
            farmStartTimeAfterUpdate,
            newStartTime,
            timeDelta,
            lastFundUpdateTime
        );
    }

    // the above fuzz test contains very low range for newStartTime on the negative delta side and further it there is a chance it can miss the no delta case.
    // so wrote the below tests.

    function testFuzz_updateFarmStartTime_end_time_withDelta(bool lockup, uint256 newStartTime) public {
        uint256 initialStartTime = block.timestamp + 50 days;
        newStartTime = bound(newStartTime, block.timestamp, type(uint64).max);

        address farm = createFarm(initialStartTime, lockup);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > initialStartTime) {
            timeDelta = newStartTime - initialStartTime;
        } else if (newStartTime < initialStartTime) {
            timeDelta = initialStartTime - newStartTime;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);

        ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 farmStartTimeAfterUpdate = ExpirableFarm(farm).farmStartTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        _assertHelper(
            initialStartTime,
            farmEndTimeBeforeUpdate,
            farmEndTimeAfterUpdate,
            farmStartTimeAfterUpdate,
            newStartTime,
            timeDelta,
            lastFundUpdateTime
        );
    }

    function testFuzz_updateFarmStartTime_end_time_noDelta(bool lockup, uint256 initialStartTime) public {
        initialStartTime = bound(initialStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(initialStartTime, lockup);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(initialStartTime);
        ExpirableFarm(farm).updateFarmStartTime(initialStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 farmStartTimeAfterUpdate = ExpirableFarm(farm).farmStartTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - initialStartTime);
        assertEq(farmEndTimeBeforeUpdate, farmEndTimeAfterUpdate);
        assertEq(farmStartTimeAfterUpdate, initialStartTime);
        assertEq(lastFundUpdateTime, 0);
    }

    function testFuzz_updateFarmStartTime_end_time_withDelta_multiUpdate(bool lockup) public {
        uint256 initialStartTime = block.timestamp + 50 days;
        uint256 newStartTime;
        address farm = createFarm(initialStartTime, lockup);

        vm.startPrank(owner);
        for (uint256 i; i < 8; ++i) {
            vm.warp(block.timestamp + 1 days);
            newStartTime = block.timestamp + (i + 1) * 10 days;
            ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        }
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 farmStartTimeAfterUpdate = ExpirableFarm(farm).farmStartTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
        assertEq(farmStartTimeAfterUpdate, newStartTime);
        assertEq(lastFundUpdateTime, 0);
    }
}

abstract contract ExtendFarmDurationTest is ExpirableFarmTest {
    function test_ExtendFarmDuration_RevertWhen_FarmNotYetStarted() public {
        uint256 extensionDays = 200;
        uint256 farmStartTime = block.timestamp + 50 days;
        address farm = createFarm(farmStartTime, false);
        vm.expectRevert(abi.encodeWithSelector(ExpirableFarm.FarmNotYetStarted.selector));
        vm.startPrank(owner);
        ExpirableFarm(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_ExtendFarmDuration_RevertWhen_InvalidExtension() public useKnownActor(owner) {
        uint256 extensionDays = 99;
        vm.expectRevert(abi.encodeWithSelector(ExpirableFarm.InvalidExtension.selector));
        ExpirableFarm(nonLockupFarm).extendFarmDuration(extensionDays);
        extensionDays = 301;
        vm.expectRevert(abi.encodeWithSelector(ExpirableFarm.InvalidExtension.selector));
        ExpirableFarm(nonLockupFarm).extendFarmDuration(extensionDays);
    }

    function test_ExtendFarmDuration_RevertWhen_farmClosed() public useKnownActor(owner) {
        uint256 extensionDays = 200;
        ExpirableFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        ExpirableFarm(nonLockupFarm).extendFarmDuration(extensionDays);
    }

    function test_ExtendFarmDuration_RevertWhen_farmExpired() public {
        uint256 extensionDays = 200;
        uint256 farmStartTime = block.timestamp + 50 days;
        address farm = createFarm(farmStartTime, false);
        uint256 farmEndTime = ExpirableFarm(farm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        vm.startPrank(owner);
        ExpirableFarm(farm).extendFarmDuration(extensionDays);
        vm.stopPrank();
    }

    function test_ExtendFarmDuration_RevertWhen_DurationExceeded() public {
        vm.startPrank(owner);
        uint256 maxExtensionDays = (
            block.timestamp + ExpirableFarm(lockupFarm).MAX_EXTENSION() * 1 days
                - ExpirableFarm(lockupFarm).farmEndTime()
        ) / 1 days;
        uint256 durationExceed = maxExtensionDays + 1;
        uint256 extensionFeePerDay = FarmRegistry(FARM_REGISTRY).extensionFeePerDay();
        address feeToken = FarmRegistry(FARM_REGISTRY).feeToken();
        uint256 extensionFeeAmount = durationExceed * extensionFeePerDay;
        IERC20(feeToken).approve(lockupFarm, extensionFeeAmount);

        vm.expectRevert(abi.encodeWithSelector(ExpirableFarm.DurationExceeded.selector));
        ExpirableFarm(lockupFarm).extendFarmDuration(durationExceed);
    }

    function testFuzz_extendFarmDuration(bool lockup, uint256 extensionDays, uint256 farmStartTime) public {
        // vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
        uint256 maxExtensionDays = (
            block.timestamp + ExpirableFarm(lockupFarm).MAX_EXTENSION() * 1 days
                - ExpirableFarm(lockupFarm).farmEndTime()
        ) / 1 days;
        extensionDays = bound(extensionDays, MIN_EXTENSION, maxExtensionDays);
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, lockup);
        vm.warp(farmStartTime + 1);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();

        uint256 extensionFeePerDay = FarmRegistry(FARM_REGISTRY).extensionFeePerDay();
        address feeReceiver = FarmRegistry(FARM_REGISTRY).feeReceiver();
        address feeToken = FarmRegistry(FARM_REGISTRY).feeToken();
        uint256 extensionFeeAmount = extensionDays * extensionFeePerDay;

        uint256 feeReceiverTokenBalanceBeforeExtension = IERC20(feeToken).balanceOf(feeReceiver);

        vm.startPrank(owner);
        IERC20(feeToken).approve(farm, 500 * 1e20);

        if (extensionFeePerDay != 0) {
            vm.expectEmit(address(farm));
            emit ExtensionFeeCollected(feeToken, extensionFeeAmount);
        }
        vm.expectEmit(address(farm));
        emit FarmEndTimeUpdated(farmEndTimeBeforeUpdate + extensionDays * 1 days);

        ExpirableFarm(farm).extendFarmDuration(extensionDays);
        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        vm.stopPrank();

        uint256 feeReceiverTokenBalanceAfterExtension = IERC20(feeToken).balanceOf(feeReceiver);

        assertEq(farmEndTimeAfterUpdate, farmEndTimeBeforeUpdate + extensionDays * 1 days);
        assertTrue(feeReceiverTokenBalanceAfterExtension > feeReceiverTokenBalanceBeforeExtension);
        assertEq(feeReceiverTokenBalanceAfterExtension, feeReceiverTokenBalanceBeforeExtension + extensionFeeAmount);
    }
}

abstract contract WithdrawWithExpiryTest is ExpirableFarmTest {
    function _assertHelper(address depositor, uint256 liquidity, uint256 expiryDate, uint256 cooldownPeriod) internal {
        assertEq(depositor, address(0));
        assertEq(liquidity, 0);
        assertEq(expiryDate, 0);
        assertEq(cooldownPeriod, 0);
    }

    function testFuzz_withdraw_notClosedButExpired() public {
        uint256 depositId = 1;
        for (uint8 i; i < 2; ++i) {
            bool lockup = i == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            ExpirableFarm(farm).getRewardBalance(rwdTokens[0]);
            uint256 currentTimestamp = block.timestamp;
            vm.warp(ExpirableFarm(farm).farmEndTime() + 1);
            vm.startPrank(user);
            vm.expectEmit(address(farm));
            emit DepositWithdrawn(depositId);
            ExpirableFarm(farm).withdraw(depositId);
            Deposit memory depositInfo = ExpirableFarm(farm).getDepositInfo(depositId);
            _assertHelper(
                depositInfo.depositor, depositInfo.liquidity, depositInfo.expiryDate, depositInfo.cooldownPeriod
            );
            vm.warp(currentTimestamp); // reset the time
        }
    }

    function testFuzz_withdraw_closedAndExpired() public {
        uint256 depositId = 1;
        for (uint8 i; i < 2; ++i) {
            bool lockup = i == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            ExpirableFarm(farm).getRewardBalance(rwdTokens[0]);
            uint256 currentTimestamp = block.timestamp;
            vm.warp(ExpirableFarm(farm).farmEndTime() - 100);
            vm.startPrank(owner);
            ExpirableFarm(farm).closeFarm(); // if farm is closed it is also paused
            vm.warp(ExpirableFarm(farm).farmEndTime() + 1);
            vm.startPrank(user);
            vm.expectEmit(address(farm));
            emit DepositWithdrawn(depositId);
            ExpirableFarm(farm).withdraw(depositId);
            Deposit memory depositInfo = ExpirableFarm(farm).getDepositInfo(depositId);
            _assertHelper(
                depositInfo.depositor, depositInfo.liquidity, depositInfo.expiryDate, depositInfo.cooldownPeriod
            );
            vm.warp(currentTimestamp); // reset the time
        }
    }
}

// Not testing expiry for other functions like ClaimRewards, AddRewards, SetRewardRate, etc. as it will be redundant.
// The above test cases are enough to cover the expiry logic and catch any changes in the expiry logic.
// We need to make sure we are not removing the farm active checks from the non-tested functions in the contracts.
// Even if we remove farm active checks by mistake, the tests in Farm.t.sol will catch them due to its transient nature.
abstract contract ExpirableFarmInheritTest is
    UpdateFarmStartTimeWithExpiryTest,
    ExtendFarmDurationTest,
    WithdrawWithExpiryTest
{}
