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
