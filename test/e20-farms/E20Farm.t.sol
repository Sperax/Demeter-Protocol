// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FarmTest} from "../Farm.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Farm} from "../../contracts/Farm.sol";
import {E20Farm} from "../../contracts/e20-farms/E20Farm.sol";
import {OperableDeposit} from "../../contracts/features/OperableDeposit.sol";
import "../Farm.t.sol";
import "../features/ExpirableFarm.t.sol";

abstract contract E20FarmTest is FarmTest {
    uint256 public constant DEPOSIT_ID = 1;
    uint256 public constant AMOUNT = 10000;

    function getPoolAddress() public virtual returns (address);
}

abstract contract E20FarmDepositTest is E20FarmTest {
    function test_E20FarmDeposit() public useKnownActor(user) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            address poolAddress = getPoolAddress();
            uint256 amt = 1e3 * 10 ** ERC20(poolAddress).decimals();
            deal(poolAddress, currentActor, amt);
            ERC20(poolAddress).approve(address(farm), amt);
            uint256 usrBalanceBefore = ERC20(poolAddress).balanceOf(currentActor);
            uint256 farmBalanceBefore = ERC20(poolAddress).balanceOf(farm);
            if (!lockup) {
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(Farm(farm).totalDeposits() + 1, COMMON_FUND_ID);
            } else {
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(Farm(farm).totalDeposits() + 1, COMMON_FUND_ID);
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(Farm(farm).totalDeposits() + 1, LOCKUP_FUND_ID);
            }
            vm.expectEmit(address(farm));
            emit IFarm.Deposited(Farm(farm).totalDeposits() + 1, currentActor, lockup, amt);
            E20Farm(farm).deposit(amt, lockup);
            uint256 usrBalanceAfter = ERC20(poolAddress).balanceOf(currentActor);
            uint256 farmBalanceAfter = ERC20(poolAddress).balanceOf(farm);
            assertEq(usrBalanceAfter, usrBalanceBefore - amt);
            assertEq(farmBalanceAfter, farmBalanceBefore + amt);
        }
    }
}

abstract contract E20FarmWithdrawTest is E20FarmTest {
    function test_revertWhen_withdraw_withdrawInSameTransactionAsIncrease()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        uint256 amt = 500 * 10 ** ERC20(poolAddress).decimals();

        deal(poolAddress, user, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        E20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        vm.expectRevert(abi.encodeWithSelector(IFarm.WithdrawTooSoon.selector));
        E20Farm(lockupFarm).withdraw(DEPOSIT_ID);
    }
}

abstract contract IncreaseDepositTest is E20FarmTest {
    function test_IncreaseDeposit_RevertWhen_InvalidAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        uint256 amt = 0;

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.expectRevert(abi.encodeWithSelector(E20Farm.InvalidAmount.selector));
        E20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function test_IncreaseDeposit_RevertWhen_FarmIsInactive()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();

        uint256 amt = 100 * 10 ** ERC20(poolAddress).decimals();

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.startPrank(owner);
        E20Farm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsInactive.selector));
        E20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function test_IncreaseDeposit_RevertWhen_depositInCoolDown()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        uint256 amt = 100 * 10 ** ERC20(poolAddress).decimals();
        E20Farm(lockupFarm).initiateCooldown(DEPOSIT_ID);
        skip(1 days * 2);
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositIsInCooldown.selector));
        E20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function testFuzz_IncreaseDepositTest(bool lockup, uint256 amt) public {
        address farm = lockup ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, lockup);
        vm.startPrank(user);
        address poolAddress = getPoolAddress();
        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());

        deal(poolAddress, user, amt);
        uint256 usrBalanceBefore = ERC20(poolAddress).balanceOf(user);
        uint256 farmBalanceBefore = ERC20(poolAddress).balanceOf(farm);
        ERC20(poolAddress).approve(address(farm), amt);
        E20Farm(farm).increaseDeposit(DEPOSIT_ID, amt);
        uint256 usrBalanceAfter = ERC20(poolAddress).balanceOf(user);
        uint256 farmBalanceAfter = ERC20(poolAddress).balanceOf(farm);
        assertEq(usrBalanceAfter, usrBalanceBefore - amt);
        assertEq(farmBalanceAfter, farmBalanceBefore + amt);
    }

    function testMaths_updateSubscriptionForIncrease() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address[] memory farmRewardTokens = getRewardTokens(nonLockupFarm);
        uint256 totalRewardClaimed = 0;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory rewardRates = Farm(nonLockupFarm).getRewardRates(rewardTokens[0]);
        address poolAddress = getPoolAddress();
        deposit(nonLockupFarm, false, 1e3);
        uint256 time = 2 days;
        uint256 amt = 1e3 * 10 ** ERC20(poolAddress).decimals();
        uint256[][] memory rewardsForEachSubs1 = new uint256[][](1);
        uint256[][] memory rewardsForEachSubs2 = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs1 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);
        //since the Deposit AMOUNTs are the same, The reward AMOUNTs should be the same.

        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i]);
        }
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);

        // We increased the first deposit by 100%
        E20Farm(nonLockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];

        assertEq(totalRewardClaimed, time * rewardRates[0]);

        skip(time);
        rewardsForEachSubs1 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);

        //The first Deposit AMOUNT is the double than the second one so the the ratio should be 2/3 and 1/3
        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], 2 * rewardsForEachSubs2[0][i]);
        }
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID);
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, 2 * time * rewardRates[0]);
    }
}

abstract contract RecoverERC20E20FarmTest is E20FarmTest {
    function test_RecoverERC20_RevertWhen_CannotWithdrawFarmToken() public useKnownActor(owner) {
        address farmToken = E20Farm(lockupFarm).farmToken();
        vm.expectRevert(abi.encodeWithSelector(E20Farm.CannotWithdrawFarmToken.selector));
        E20Farm(lockupFarm).recoverERC20(farmToken);
    }
}

abstract contract DecreaseDepositTest is E20FarmTest {
    function test_revertWhen_decreaseDeposit_decreaseInSameTransactionAsIncrease()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        uint256 amt = 500 * 10 ** ERC20(poolAddress).decimals();

        deal(poolAddress, user, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        E20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        vm.expectRevert(abi.encodeWithSelector(IFarm.WithdrawTooSoon.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, amt);
    }

    function test_decreaseDeposit_decreaseInSameTransactionAsDeposit()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(IFarm.WithdrawTooSoon.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function test_zeroAmount() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 amount;
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(IFarm.CannotWithdrawZeroAmount.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, amount);
    }

    function test_CannotWithdrawZeroAmount() public depositSetup(lockupFarm, true) useKnownActor(user) {
        skip(1 days * 7);
        vm.expectRevert(abi.encodeWithSelector(IFarm.CannotWithdrawZeroAmount.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, 0);
    }

    function test_InsufficientLiquidity() public depositSetup(lockupFarm, true) useKnownActor(user) {
        skip(1 days * 7);
        Deposit memory depositInfo = E20Farm(lockupFarm).getDepositInfo(DEPOSIT_ID);
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.InsufficientLiquidity.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, depositInfo.liquidity + 1);
    }

    function test_DecreaseDeposit_RevertWhen_LockupFarm_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(1 days * 7);
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        E20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function test_DecreaseDeposit_RevertWhen_farmIsClosed()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(owner)
    {
        skip(1 days * 7);
        E20Farm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsClosed.selector));
        E20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function test_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        skip(1 days * 7);
        E20Farm(nonLockupFarm).computeRewards(currentActor, 1);
        E20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function testMaths_updateSubscriptionForDecrease() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address[] memory farmRewardTokens = getRewardTokens(nonLockupFarm);
        uint256 totalRewardClaimed = 0;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory rewardRates = Farm(nonLockupFarm).getRewardRates(rewardTokens[0]);
        address poolAddress = getPoolAddress();
        deposit(nonLockupFarm, false, 1e3);
        uint256 time = 2 days;
        uint256 amt = 1e3 * 10 ** ERC20(poolAddress).decimals();
        uint256[][] memory rewardsForEachSubs1 = new uint256[][](1);
        uint256[][] memory rewardsForEachSubs2 = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs1 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);
        //since the Deposit amounts are the same, The reward amounts should be the same.

        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i]);
        }
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);

        // We withdrew 50% of the deposit
        E20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, amt / 2);
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, time * rewardRates[0]);

        skip(time);
        rewardsForEachSubs1 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2 = Farm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);

        //The first Deposit amount is the half than the second one so the the ratio should be 1/3 and 2/3
        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i] / 2);
        }
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID);
        Farm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, 2 * time * rewardRates[0]);
    }
}

abstract contract E20FarmInheritTest is
    E20FarmDepositTest,
    E20FarmWithdrawTest,
    IncreaseDepositTest,
    RecoverERC20E20FarmTest,
    DecreaseDepositTest
{}
