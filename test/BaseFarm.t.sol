// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import { BaseFarm } from "../contracts/BaseFarm.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PreMigrationSetup } from "../test/utils/DeploymentSetup.sol";
import { FarmFactory } from "../../contracts/farmFactory.sol";
import { BaseFarmDeployer } from "../../contracts/BaseFarmDeployer.sol";
import { BaseFarm, RewardTokenData } from "../../contracts/BaseFarm.sol";
import { Demeter_BalancerFarm } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm.sol";
import { Demeter_BalancerFarm_Deployer } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";
import { console } from "forge-std/console.sol";

contract BaseFarmTest is PreMigrationSetup {
  struct RewardData {
    address tknManager;
    uint8 id;
    uint256 accRewardBal;
  }

  mapping(address => RewardData) public rewardData;
  event Deposited(
    address indexed account,
    bool locked,
    uint256 tokenId,
    uint256 liquidity
  );
  event CooldownInitiated(
    address indexed account,
    uint256 tokenId,
    uint256 expiryDate
  );
  event DepositWithdrawn(
    address indexed account,
    uint256 tokenId,
    uint256 startTime,
    uint256 liquidity,
    uint256[] totalRewardsClaimed
  );
  event RewardsClaimed(
    address indexed account,
    uint8 fundId,
    uint256 tokenId,
    uint256 liquidity,
    uint256 fundLiquidity,
    uint256[] rewardAmount
  );
  event PoolUnsubscribed(
    address indexed account,
    uint8 fundId,
    uint256 depositId,
    uint256 startTime,
    uint256[] totalRewardsClaimed
  );
  event FarmStartTimeUpdated(uint256 newStartTime);
  event CooldownPeriodUpdated(
    uint256 oldCooldownPeriod,
    uint256 newCooldownPeriod
  );
  event RewardRateUpdated(
    address rwdToken,
    uint256[] oldRewardRate,
    uint256[] newRewardRate
  );
  event RewardAdded(address rwdToken, uint256 amount);
  event FarmClosed();
  event RecoveredERC20(address token, uint256 amount);
  event FundsRecovered(
    address indexed account,
    address rwdToken,
    uint256 amount
  );
  event TokenManagerUpdated(
    address rwdToken,
    address oldTokenManager,
    address newTokenManager
  );
  event RewardTokenAdded(address rwdToken, address rwdTokenManager);
  event FarmPaused(bool paused);

  function setUp() public virtual override {
    super.setUp();
    createNonLockupFarm(block.timestamp);

    createLockupFarm(block.timestamp);
  }

  function setupFarmRewards() public {
    addRewards(nonLockupFarm);
    addRewards(lockupFarm);
  }
}

contract addRewards is BaseFarmTest {
  function test_nonLockupFarm_revertsWhen_invalidRwdToken(uint256 rwdAmt)
    public
    useActor(0)
  {
    bound(
      rwdAmt,
      1000 * 10**ERC20(VST).decimals(),
      1000000 * 10**ERC20(VST).decimals()
    );
    deal(address(VST), currentActor, rwdAmt);
    ERC20(VST).approve(address(nonLockupFarm), rwdAmt);
    vm.expectRevert("Invalid reward token");
    nonLockupFarm.addRewards(VST, rwdAmt);
  }

  function test_lockupFarm_revertsWhen_invalidRwdToken(uint256 rwdAmt)
    public
    useActor(1)
  {
    bound(
      rwdAmt,
      1000 * 10**ERC20(VST).decimals(),
      1000000 * 10**ERC20(VST).decimals()
    );
    deal(address(VST), currentActor, rwdAmt);
    ERC20(VST).approve(address(lockupFarm), rwdAmt);
    vm.expectRevert("Invalid reward token");
    lockupFarm.addRewards(VST, rwdAmt);
  }

  // function test_lockupFarm_revertsWhen_noAmount(uint256 rwdAmt)
  //   public
  //   useActor(1)
  // {
  //   bound(rwdAmt, 0, 1000000 * 10**ERC20(USDCe).decimals());
  //   vm.expectRevert(bytes(""));
  //   lockupFarm.addRewards(USDCe, rwdAmt);
  // }

  function test_nonLockupFarm(uint256 rwdAmt) public useActor(0) {
    address[] memory rewardTokens = nonLockupFarm.getRewardTokens();

    for (uint8 i; i < rewardTokens.length; ++i) {
      bound(
        rwdAmt,
        1000 * 10**ERC20(rewardTokens[i]).decimals(),
        1000000 * 10**ERC20(rewardTokens[i]).decimals()
      );
      deal(address(rewardTokens[i]), currentActor, rwdAmt);
      ERC20(rewardTokens[i]).approve(address(nonLockupFarm), rwdAmt);
      vm.expectEmit(true, true, false, true);
      emit RewardAdded(rewardTokens[i], rwdAmt);
      nonLockupFarm.addRewards(rewardTokens[i], rwdAmt);
      assertEq(nonLockupFarm.getRewardBalance(rewardTokens[i]), rwdAmt);
    }
  }

  function test_lockupFarm(uint256 rwdAmt) public useActor(1) {
    address[] memory rewardTokens = lockupFarm.getRewardTokens();
    for (uint8 i; i < rewardTokens.length; ++i) {
      bound(
        rwdAmt,
        1000 * 10**ERC20(rewardTokens[i]).decimals(),
        1000000 * 10**ERC20(rewardTokens[i]).decimals()
      );
      deal(address(rewardTokens[i]), currentActor, rwdAmt);
      ERC20(rewardTokens[i]).approve(address(lockupFarm), rwdAmt);
      vm.expectEmit(true, true, false, true);
      emit RewardAdded(rewardTokens[i], rwdAmt);
      lockupFarm.addRewards(rewardTokens[i], rwdAmt);
      assertEq(lockupFarm.getRewardBalance(rewardTokens[i]), rwdAmt);
    }
  }
}

contract setRewardRate is BaseFarmTest {
  function test_noLockupFarm_revertsWhen_invalidLength(uint256 rwdRateNonLockup)
    public
    useActor(1)
  {
    uint256[] memory rwdRate = new uint256[](1);
    rwdRate[0] = rwdRateNonLockup;
    address[] memory rewardTokens = nonLockupFarm.getRewardTokens();
    uint256[] memory oldRewardRate = new uint256[](1);
    for (uint8 i; i < rewardTokens.length; ++i) {
      oldRewardRate = nonLockupFarm.getRewardRates(rewardTokens[i]);
      bound(
        rwdRateNonLockup,
        1 * 10**ERC20(rewardTokens[i]).decimals(),
        2 * 10**ERC20(rewardTokens[i]).decimals()
      );
      if (rewardTokens[i] == SPA) {
        vm.startPrank(SPA_MANAGER);
      } else {
        vm.startPrank(currentActor);
      }

      vm.expectRevert("Invalid reward rates length");

      lockupFarm.setRewardRate(rewardTokens[i], rwdRate);
    }
  }

  function test_noLockupFarm(uint256 rwdRateNonLockup) public useActor(0) {
    uint256[] memory rwdRate = new uint256[](1);
    rwdRate[0] = rwdRateNonLockup;
    address[] memory rewardTokens = nonLockupFarm.getRewardTokens();
    uint256[] memory oldRewardRate = new uint256[](1);
    for (uint8 i; i < rewardTokens.length; ++i) {
      oldRewardRate = nonLockupFarm.getRewardRates(rewardTokens[i]);
      bound(
        rwdRateNonLockup,
        1 * 10**ERC20(rewardTokens[i]).decimals(),
        2 * 10**ERC20(rewardTokens[i]).decimals()
      );
      if (rewardTokens[i] == SPA) {
        vm.startPrank(SPA_MANAGER);
      } else {
        vm.startPrank(currentActor);
      }

      vm.expectEmit(true, true, false, true);
      emit RewardRateUpdated(rewardTokens[i], oldRewardRate, rwdRate);
      nonLockupFarm.setRewardRate(rewardTokens[i], rwdRate);
      assertEq(nonLockupFarm.getRewardRates(rewardTokens[i]), rwdRate);
    }
  }

  function test_LockupFarm(uint256 rwdRateNonLockup, uint256 rwdRateLockup)
    public
    useActor(1)
  {
    uint256[] memory rwdRate = new uint256[](2);
    rwdRate[0] = rwdRateNonLockup;
    rwdRate[1] = rwdRateLockup;
    address[] memory rewardTokens = lockupFarm.getRewardTokens();
    uint256[] memory oldRewardRate = new uint256[](2);
    for (uint8 i; i < rewardTokens.length; ++i) {
      oldRewardRate = nonLockupFarm.getRewardRates(rewardTokens[i]);
      bound(
        rwdRateNonLockup,
        1 * 10**ERC20(rewardTokens[i]).decimals(),
        2 * 10**ERC20(rewardTokens[i]).decimals()
      );
      bound(
        rwdRateLockup,
        2 * 10**ERC20(rewardTokens[i]).decimals(),
        4 * 10**ERC20(rewardTokens[i]).decimals()
      );
      if (rewardTokens[i] == SPA) {
        vm.startPrank(SPA_MANAGER);
      } else {
        vm.startPrank(currentActor);
      }

      vm.expectEmit(true, false, false, false);
      emit RewardRateUpdated(rewardTokens[i], oldRewardRate, rwdRate);
      lockupFarm.setRewardRate(rewardTokens[i], rwdRate);
      assertEq(lockupFarm.getRewardRates(rewardTokens[i]), rwdRate);
    }
  }
}

contract farmPauseSwitch is BaseFarmTest {
  function test_noLockupFarm_revertsWhen_farmIntheSameState(bool _isPaused)
    public
    useActor(0)
  {
    bool isPaused = nonLockupFarm.isPaused();
    vm.assume(_isPaused == isPaused);
    vm.expectRevert("Farm already in required state");
    nonLockupFarm.farmPauseSwitch(_isPaused);
  }

  function test_lockupFarm_revertsWhen_farmIntheSameState(bool _isPaused)
    public
    useActor(1)
  {
    bool isPaused = lockupFarm.isPaused();
    vm.assume(_isPaused == isPaused);
    vm.expectRevert("Farm already in required state");
    lockupFarm.farmPauseSwitch(_isPaused);
  }

  function test_noLockupFarm_revertsWhen_farmClosed(bool _isPaused)
    public
    useActor(0)
  {
    bool isPaused = nonLockupFarm.isPaused();
    vm.assume(_isPaused != isPaused);
    nonLockupFarm.closeFarm();
    vm.expectRevert("Farm closed");
    nonLockupFarm.farmPauseSwitch(_isPaused);
  }

  function test_lockupFarm_revertsWhen_farmClosed(bool _isPaused)
    public
    useActor(1)
  {
    bool isPaused = lockupFarm.isPaused();
    vm.assume(_isPaused != isPaused);
    lockupFarm.closeFarm();
    vm.expectRevert("Farm closed");
    lockupFarm.farmPauseSwitch(_isPaused);
  }

  function test_noLockupFarm(bool _isPaused) public useActor(0) {
    bool isPaused = nonLockupFarm.isPaused();
    vm.assume(_isPaused != isPaused);
    vm.expectEmit(true, true, false, true);
    emit FarmPaused(_isPaused);
    nonLockupFarm.farmPauseSwitch(_isPaused);
  }

  function test_lockupFarm(bool _isPaused) public useActor(1) {
    bool isPaused = lockupFarm.isPaused();
    vm.assume(_isPaused != isPaused);
    vm.expectEmit(true, true, false, true);
    emit FarmPaused(_isPaused);
    lockupFarm.farmPauseSwitch(_isPaused);
  }
}

contract updateFarmStartTime is BaseFarmTest {
  function test_noLockupFarm_revertsWhen_farmStarted() public useActor(0) {
    vm.expectRevert("Farm already started");
    nonLockupFarm.updateFarmStartTime(block.timestamp);
  }

  function test_lockupFarm_revertsWhen_farmStarted() public useActor(1) {
    vm.expectRevert("Farm already started");
    lockupFarm.updateFarmStartTime(block.timestamp);
  }

  function test_noLockupFarm_revertsWhen_incorrectTime() public {
    createNonLockupFarm(block.timestamp + 200);
    vm.startPrank(actors[0]);
    vm.expectRevert("Time < now");
    nonLockupFarm.updateFarmStartTime(block.timestamp - 1);
  }

  function test_lockupFarm_revertsWhen_incorrectTime() public {
    createLockupFarm(block.timestamp + 200);
    vm.startPrank(actors[1]);
    vm.expectRevert("Time < now");
    lockupFarm.updateFarmStartTime(block.timestamp - 1);
  }

  function test_noLockupFarm(uint256 farmStartTime, uint256 newStartTime)
    public
  {
    vm.assume(
      farmStartTime > block.timestamp + 2 && newStartTime == farmStartTime - 1
    );
    createNonLockupFarm(farmStartTime);
    vm.startPrank(actors[0]);
    vm.expectEmit(true, true, false, true);
    emit FarmStartTimeUpdated(newStartTime);
    nonLockupFarm.updateFarmStartTime(newStartTime);
  }

  function test_lockupFarm(uint256 farmStartTime, uint256 newStartTime) public {
    vm.assume(
      farmStartTime > block.timestamp + 2 && newStartTime == farmStartTime - 1
    );

    createLockupFarm(farmStartTime);
    vm.startPrank(actors[1]);
    vm.expectEmit(true, true, false, true);
    emit FarmStartTimeUpdated(newStartTime);
    lockupFarm.updateFarmStartTime(newStartTime);
  }
}

contract updateCoolDownPeriod is BaseFarmTest {
  function test_noLockupFarm(uint256 cooldownPeriod) public useActor(0) {
    bound(cooldownPeriod, 1, 30);
    vm.expectRevert("Farm does not support lockup");
    nonLockupFarm.updateCooldownPeriod(cooldownPeriod);
  }

  function test_noLockupFarm_revertsWhen_Closed(uint256 cooldownPeriod)
    public
    useActor(0)
  {
    bound(cooldownPeriod, 1, 30);
    nonLockupFarm.closeFarm();
    vm.expectRevert("Farm closed");
    nonLockupFarm.updateCooldownPeriod(cooldownPeriod);
  }

  function test_lockupFarm_revertsWhen_nonValidCooldownPeriod(
    uint256 cooldownPeriod
  ) public useActor(1) {
    vm.assume(cooldownPeriod > 30 && cooldownPeriod < 720);
    vm.expectRevert("Invalid cooldown period");
    lockupFarm.updateCooldownPeriod(cooldownPeriod);
  }

  function test_lockupFarm_revertsWhen_cooldownPeriod0(uint256 cooldownPeriod)
    public
    useActor(1)
  {
    vm.assume(cooldownPeriod == 0);
    vm.expectRevert("Invalid cooldown period");
    lockupFarm.updateCooldownPeriod(cooldownPeriod);
  }

  function test_lockupFarm(uint256 cooldownPeriod) public useActor(1) {
    vm.assume(cooldownPeriod > 0 && cooldownPeriod < 31);

    vm.expectEmit(true, true, false, true);
    emit CooldownPeriodUpdated(COOLDOWN_PERIOD, cooldownPeriod);
    lockupFarm.updateCooldownPeriod(cooldownPeriod);
  }
}
