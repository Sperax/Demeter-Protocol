// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarmTest} from "../BaseFarm.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseFarm} from "../../contracts/BaseFarm.sol";
import {BaseE20Farm} from "../../contracts/e20-farms/BaseE20Farm.sol";
import {OperableDeposit} from "../../contracts/OperableDeposit.sol";
import "../BaseFarm.t.sol";
import "../features/BaseFarmWithExpiry.t.sol";

abstract contract BaseE20FarmTest is BaseFarmTest {
    uint256 public constant DEPOSIT_ID = 1;
    uint256 public constant AMOUNT = 10000;

    function getPoolAddress() public virtual returns (address);
}

abstract contract IncreaseDepositTest is BaseE20FarmTest {
    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);

    function test_RevertWhen_InvalidAmount() public depositSetup(lockupFarm, true) useKnownActor(user) {
        address poolAddress = getPoolAddress();
        uint256 amt = 0;

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.InvalidAmount.selector));
        BaseE20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function testFuzz_RevertWhen_farmIsClosed(uint256 amt) public depositSetup(lockupFarm, true) useKnownActor(user) {
        address poolAddress = getPoolAddress();

        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.startPrank(owner);
        BaseE20Farm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseE20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function testFuzz_RevertWhen_depositInCoolDown(uint256 amt)
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());
        BaseE20Farm(lockupFarm).initiateCooldown(DEPOSIT_ID);
        skip(86400 * 2);
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.DepositInCooldown.selector));
        BaseE20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
    }

    function testFuzz_lockupFarm(uint256 amt) public depositSetup(lockupFarm, true) useKnownActor(user) {
        address poolAddress = getPoolAddress();
        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());

        deal(poolAddress, currentActor, amt);
        uint256 usrBalanceBefore = ERC20(poolAddress).balanceOf(currentActor);
        uint256 farmBalanceBefore = ERC20(poolAddress).balanceOf(lockupFarm);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        BaseE20Farm(lockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        uint256 usrBalanceAfter = ERC20(poolAddress).balanceOf(currentActor);
        uint256 farmBalanceAfter = ERC20(poolAddress).balanceOf(lockupFarm);
        assertEq(usrBalanceAfter, usrBalanceBefore - amt);
        assertEq(farmBalanceAfter, farmBalanceBefore + amt);
    }

    function testFuzz_nonLockupFarm(uint256 amt) public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address poolAddress = getPoolAddress();
        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());

        deal(poolAddress, currentActor, amt);
        uint256 usrBalanceBefore = ERC20(poolAddress).balanceOf(currentActor);
        uint256 farmBalanceBefore = ERC20(poolAddress).balanceOf(nonLockupFarm);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);
        BaseE20Farm(nonLockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        uint256 usrBalanceAfter = ERC20(poolAddress).balanceOf(currentActor);
        uint256 farmBalanceAfter = ERC20(poolAddress).balanceOf(nonLockupFarm);
        assertEq(usrBalanceAfter, usrBalanceBefore - amt);
        assertEq(farmBalanceAfter, farmBalanceBefore + amt);
    }

    function testMaths_updateSubscriptionForIncrease() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address[] memory farmRewardTokens = getRewardTokens(nonLockupFarm);
        uint256 totalRewardClaimed = 0;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory rewardRates = new uint256[](rewardTokens.length);
        rewardRates = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[0]);
        address poolAddress = getPoolAddress();
        deposit(nonLockupFarm, false, 1e3);
        uint256 time = 2 days;
        uint256 amt = 1e3 * 10 ** ERC20(poolAddress).decimals();
        uint256[][] memory rewardsForEachSubs1 = new uint256[][](1);
        uint256[][] memory rewardsForEachSubs2 = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs1[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);
        //since the Deposit AMOUNTs are the same, The reward AMOUNTs should be the same.

        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i]);
        }
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);

        // We increased the first deposit by 100%
        BaseE20Farm(nonLockupFarm).increaseDeposit(DEPOSIT_ID, amt);
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];

        assertEq(totalRewardClaimed, time * rewardRates[0]);

        skip(time);
        rewardsForEachSubs1[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);

        //The first Deposit AMOUNT is the double than the second one so the the ratio should be 2/3 and 1/3
        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], 2 * rewardsForEachSubs2[0][i]);
        }
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID);
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, 2 * time * rewardRates[0]);
    }
}

abstract contract RecoverERC20E20FarmTest is BaseE20FarmTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_recoverE20_LockupFarm_RevertWhen_CannotWithdrawRewardTokenOrFarmToken() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.CannotWithdrawRewardTokenOrFarmToken.selector));
        BaseFarm(lockupFarm).recoverERC20(USDCe);
    }

    function test_recoverE20_LockupFarm_RevertWhen_CannotWithdrawZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        BaseFarm(lockupFarm).recoverERC20(USDT);
    }

    function test_recoverE20_LockupFarm() public useKnownActor(owner) {
        uint256 amt = 1e3 * ERC20(USDT).decimals();
        deal(USDT, address(lockupFarm), amt);
        vm.expectEmit(USDT);
        emit Transfer(lockupFarm, owner, amt);
        vm.expectEmit(lockupFarm);
        emit RecoveredERC20(USDT, amt);
        BaseFarm(lockupFarm).recoverERC20(USDT);
    }
}

abstract contract DecreaseDepositTest is BaseE20FarmTest {
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    function test_zeroAmount() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 amount;
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.InvalidAmount.selector));
        BaseE20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, amount);
    }

    function test_RevertWhen_LockupFarm_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(86400 * 7);
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        BaseE20Farm(lockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function test_RevertWhen_farmIsClosed() public depositSetup(nonLockupFarm, false) useKnownActor(owner) {
        skip(86400 * 7);
        BaseE20Farm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseE20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function test_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        skip(86400 * 7);
        BaseE20Farm(nonLockupFarm).computeRewards(currentActor, 1);
        BaseE20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, AMOUNT);
    }

    function testMaths_updateSubscriptionForDecrease() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address[] memory farmRewardTokens = getRewardTokens(nonLockupFarm);
        uint256 totalRewardClaimed = 0;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory rewardRates = new uint256[](rewardTokens.length);
        rewardRates = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[0]);
        address poolAddress = getPoolAddress();
        deposit(nonLockupFarm, false, 1e3);
        uint256 time = 2 days;
        uint256 amt = 1e3 * 10 ** ERC20(poolAddress).decimals();
        uint256[][] memory rewardsForEachSubs1 = new uint256[][](1);
        uint256[][] memory rewardsForEachSubs2 = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs1[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);
        //since the Deposit amounts are the same, The reward amounts should be the same.

        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i]);
        }
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);

        // We withdrew 50% of the deposit
        BaseE20Farm(nonLockupFarm).decreaseDeposit(DEPOSIT_ID, amt / 2);
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, time * rewardRates[0]);

        skip(time);
        rewardsForEachSubs1[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID);
        rewardsForEachSubs2[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, DEPOSIT_ID + 1);

        //The first Deposit amount is the half than the second one so the the ratio should be 1/3 and 2/3
        for (uint8 i = 0; i < farmRewardTokens.length; ++i) {
            assertEq(rewardsForEachSubs1[0][i], rewardsForEachSubs2[0][i] / 2);
        }
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID);
        BaseFarm(nonLockupFarm).claimRewards(DEPOSIT_ID + 1);

        //Check if all the rewards are distributed to the deposits
        totalRewardClaimed += rewardsForEachSubs1[0][0] + rewardsForEachSubs2[0][0];
        assertEq(totalRewardClaimed, 2 * time * rewardRates[0]);
    }
}
