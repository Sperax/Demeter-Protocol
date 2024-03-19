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
        uint256 farmStartTime,
        uint256 farmEndTimeBeforeUpdate,
        uint256 farmEndTimeAfterUpdate,
        uint256 lastFundUpdateTime,
        uint256 newStartTime,
        uint256 timeDelta
    ) internal {
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

    function test_updateFarmStartTime_RevertWhen_FarmHasExpired() public useKnownActor(owner) {
        uint256 farmEndTime = ExpirableFarm(nonLockupFarm).farmEndTime();
        vm.warp(farmEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        ExpirableFarm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function testFuzz_updateFarmStartTimeWithExpiry(bool lockup, uint256 farmStartTime, uint256 newStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, farmStartTime - 1, type(uint64).max);
        address farm = createFarm(farmStartTime, lockup);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        _assertHelper(
            farmStartTime, farmEndTimeBeforeUpdate, farmEndTimeAfterUpdate, lastFundUpdateTime, newStartTime, timeDelta
        );
    }

    // the above fuzz test contains very low range for newStartTime on the negative delta side and further it there is a chance it can miss the no delta case.
    // so wrote the below tests.

    function testFuzz_updateFarmStartTime_end_time_withDelta(bool lockup, uint256 newStartTime) public {
        uint256 farmStartTime = block.timestamp + 50 days;
        newStartTime = bound(newStartTime, block.timestamp, type(uint64).max);

        address farm = createFarm(farmStartTime, lockup);
        uint256 farmEndTimeBeforeUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 timeDelta;

        if (newStartTime > farmStartTime) {
            timeDelta = newStartTime - farmStartTime;
        } else if (newStartTime < farmStartTime) {
            timeDelta = farmStartTime - newStartTime;
        }

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);

        ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        _assertHelper(
            farmStartTime, farmEndTimeBeforeUpdate, farmEndTimeAfterUpdate, lastFundUpdateTime, newStartTime, timeDelta
        );
    }

    function testFuzz_updateFarmStartTime_end_time_noDelta(bool lockup, uint256 farmStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 1, type(uint64).max);
        address farm = createFarm(farmStartTime, lockup);

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(farmStartTime);
        ExpirableFarm(farm).updateFarmStartTime(farmStartTime);
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - farmStartTime);
        assertEq(lastFundUpdateTime, farmStartTime);
    }

    function testFuzz_updateFarmStartTime_end_time_withDelta_multiUpdate(bool lockup) public {
        uint256 farmStartTime = block.timestamp + 50 days;
        uint256 newStartTime;
        address farm = createFarm(farmStartTime, lockup);

        vm.startPrank(owner);
        for (uint256 i; i < 8; ++i) {
            vm.warp(block.timestamp + 1 days);
            newStartTime = block.timestamp + (i + 1) * 10 days;
            ExpirableFarm(farm).updateFarmStartTime(newStartTime);
        }
        vm.stopPrank();

        uint256 farmEndTimeAfterUpdate = ExpirableFarm(farm).farmEndTime();
        uint256 lastFundUpdateTime = ExpirableFarm(farm).lastFundUpdateTime();

        assertEq(MIN_EXTENSION * 1 days, farmEndTimeAfterUpdate - newStartTime);
        assertEq(lastFundUpdateTime, newStartTime);
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

    function testFuzz_extendFarmDuration(bool lockup, uint256 extensionDays, uint256 farmStartTime) public {
        vm.assume(extensionDays >= MIN_EXTENSION && extensionDays <= MAX_EXTENSION);
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
    function _assertHelper(
        address depositor,
        uint256 liquidity,
        uint256 startTime,
        uint256 expiryDate,
        uint256 cooldownPeriod
    ) internal {
        assertEq(depositor, address(0));
        assertEq(liquidity, 0);
        assertEq(startTime, 0);
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
                depositInfo.depositor,
                depositInfo.liquidity,
                depositInfo.startTime,
                depositInfo.expiryDate,
                depositInfo.cooldownPeriod
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
                depositInfo.depositor,
                depositInfo.liquidity,
                depositInfo.startTime,
                depositInfo.expiryDate,
                depositInfo.cooldownPeriod
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
