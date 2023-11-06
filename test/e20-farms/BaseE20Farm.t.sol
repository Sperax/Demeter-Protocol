// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarmTest} from "../BaseFarm.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseE20Farm} from "../../contracts/e20-farms/BaseE20Farm.sol";

abstract contract BaseE20FarmTest is BaseFarmTest {}

abstract contract IncreaseDepositTest is BaseE20FarmTest {
    function test_lockupFarm(uint256 amt) public setup useKnownActor(owner) {
        address poolAddress = getPoolAddress();
        vm.assume(amt > 100 * 10 ** ERC20(poolAddress).decimals() && amt <= 1000 * 10 ** ERC20(poolAddress).decimals());

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        BaseE20Farm(lockupFarm).increaseDeposit(0, amt);
    }
}

abstract contract WithdrawPartiallyTest is BaseE20FarmTest {
    function test_zeroAmount() public setup useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.InvalidAmount.selector));
        BaseE20Farm(nonLockupFarm).withdrawPartially(0, 0);
    }

    function test_LockupFarm() public setup useKnownActor(owner) {
        skip(86400 * 7);
        vm.expectRevert(abi.encodeWithSelector(BaseE20Farm.PartialWithdrawNotPermitted.selector));
        BaseE20Farm(lockupFarm).withdrawPartially(0, 10000);
    }

    function test_nonLockupFarm() public setup useKnownActor(owner) {
        // lockupFarm.initiateCooldown(0);
        skip(86400 * 7);
        BaseE20Farm(nonLockupFarm).computeRewards(currentActor, 0);
        BaseE20Farm(nonLockupFarm).withdrawPartially(0, 10000);
    }
}
