// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarm, RewardTokenData} from "../contracts/BaseFarm.sol";
import {BaseE20Farm} from "../contracts/e20-farms/BaseE20Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {FarmFactory} from "../contracts/FarmFactory.sol";
import {BaseFarmDeployer} from "../contracts/BaseFarmDeployer.sol";

abstract contract BaseFarmTest is TestNetworkConfig {
    struct Deposit {
        uint256 liquidity;
        uint256 tokenId;
        uint256 startTime;
        uint256 expiryDate;
        uint256 cooldownPeriod;
        uint256[] totalRewardsClaimed;
    }

    struct RewardData {
        address tknManager;
        uint8 id;
        uint256 accRewardBal;
    }

    struct RewardFund {
        uint256 totalLiquidity;
        uint256[] rewardsPerSec;
        uint256[] accRewardPerShare;
    }

    uint256 public constant MIN_BALANCE = 1000000000000000000;
    uint256 public constant NO_LOCKUP_REWARD_RATE = 1e18;
    uint256 public constant LOCKUP_REWARD_RATE = 2e18;
    uint256 public constant COOLDOWN_PERIOD = 21;
    bytes32 public constant NO_LOCK_DATA = bytes32(uint256(0));
    bytes32 public constant LOCK_DATA = bytes32(uint256(1));
    address internal farmProxy;
    address internal lockupFarm;
    address internal nonLockupFarm;
    address internal invalidRewardToken;
    address[] public rwdTokens;
    address user;
    address newTokenManager;

    event Deposited(uint256 indexed depositId, address indexed account, bool locked, uint256 liquidity);
    event CooldownInitiated(uint256 indexed depositId, uint256 expiryDate);
    event DepositWithdrawn(uint256 indexed depositId);
    event RewardsClaimed(uint256 indexed depositId, uint256[][] rewardsForEachSubs);
    event PoolUnsubscribed(uint256 indexed depositId, uint8 fundId, uint256[] totalRewardsClaimed);
    event PoolSubscribed(uint256 indexed depositId, uint8 fundId);
    event FarmStartTimeUpdated(uint256 newStartTime);
    event CooldownPeriodUpdated(uint256 newCooldownPeriod);
    event RewardRateUpdated(address indexed rwdToken, uint256[] newRewardRate);
    event RewardAdded(address rwdToken, uint256 amount);
    event FarmClosed();
    event RecoveredERC20(address token, uint256 amount);
    event FundsRecovered(address indexed account, address indexed rwdToken, uint256 amount);
    event TokenManagerUpdated(address indexed rwdToken, address newTokenManager);
    event RewardTokenAdded(address indexed rwdToken, address rwdTokenManager);
    event FarmPaused(bool paused);

    modifier setup() {
        _;
    }

    modifier depositSetup(address farm, bool lockup) {
        addRewards(farm);
        setRewardRates(farm);
        deposit(farm, lockup, 1e3);
        _;
    }

    function setUp() public virtual override {
        super.setUp();
        user = actors[0];
        newTokenManager = actors[3];
    }

    function addRewards(address farm) public useKnownActor(owner) {
        address[] memory farmRewardTokens = getRewardTokens(farm);
        uint256 rwdAmt;
        for (uint8 i; i < farmRewardTokens.length; ++i) {
            rwdAmt = 1e7 * 10 ** ERC20(farmRewardTokens[i]).decimals();
            deal(address(farmRewardTokens[i]), owner, rwdAmt);
            ERC20(farmRewardTokens[i]).approve(farm, rwdAmt);
            BaseFarm(farm).addRewards(farmRewardTokens[i], rwdAmt);
        }
    }

    function setRewardRates(address farm) public useKnownActor(owner) {
        if (BaseFarm(farm).cooldownPeriod() != 0) {
            uint256[] memory rwdRate = new uint256[](2);
            address[] memory farmRewardTokens = getRewardTokens(farm);
            for (uint8 i; i < farmRewardTokens.length; ++i) {
                rwdRate[0] = 1 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.01
                rwdRate[1] = 2 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.02
                if (farmRewardTokens[i] == SPA) {
                    vm.startPrank(SPA_REWARD_MANAGER);
                } else {
                    vm.startPrank(owner);
                }
                BaseFarm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        } else {
            uint256[] memory rwdRate = new uint256[](1);
            address[] memory farmRewardTokens = getRewardTokens(farm);
            for (uint8 i; i < farmRewardTokens.length; ++i) {
                rwdRate[0] = 1 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.01
                if (farmRewardTokens[i] == SPA) {
                    vm.startPrank(SPA_REWARD_MANAGER);
                } else {
                    vm.startPrank(owner);
                }
                BaseFarm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        }
    }

    function createFarm(uint256 startTime, bool lockup) public virtual returns (address);

    function deposit(address farm, bool locked, uint256 amt) public virtual returns (uint256);

    function deposit(address farm, bool locked, uint256 amt, bytes memory revertMsg) public virtual;

    function getRewardTokens(address farm) public view returns (address[] memory) {
        address[] memory farmRewardTokens = new address[](rwdTokens.length + 1);
        for (uint8 i = 0; i < rwdTokens.length + 1; ++i) {
            farmRewardTokens[i] = BaseFarm(farm).rewardTokens(i);
        }
        return farmRewardTokens;
    }
}

abstract contract DepositTest is BaseFarmTest {
    function test_deposit_noLockupFarm_revertsWhen_NoLiquidityInPosition() public {
        deposit(nonLockupFarm, false, 0, abi.encodeWithSelector(BaseFarm.NoLiquidityInPosition.selector));
    }

    function test_deposit_noLockupFarm_revertsWhen_LockupFunctionalityIsDisabled() public {
        deposit(nonLockupFarm, true, 1e2, abi.encodeWithSelector(BaseFarm.LockupFunctionalityIsDisabled.selector));
    }

    function test_deposit_revertsWhen_FarmIsPaused() public {
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        deposit(nonLockupFarm, false, 1e2, abi.encodeWithSelector(BaseFarm.FarmIsPaused.selector));
    }

    function test_deposit_noLockupFarm_deposit() public {
        deposit(nonLockupFarm, false, 1e2);
    }

    function test_deposit_lockupFarm() public {
        deposit(lockupFarm, true, 1e2);
    }
}

abstract contract ClaimRewardsTest is BaseFarmTest {
    function test_claimRewards_lockupFarm_closed() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        skip(86400 * 2);
        BaseFarm(lockupFarm).initiateCooldown(1);
        vm.startPrank(owner);
        skip(86400 * 2);
        BaseFarm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        skip(86400 * 2);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        vm.startPrank(owner);
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(lockupFarm).claimRewards(1);
    }

    function test_claimRewards_lockupFarm_nonValidDeposit()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(86400 * 2);
        BaseFarm(lockupFarm).initiateCooldown(1);
        vm.startPrank(owner);
        skip(86400 * 2);
        BaseFarm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        skip(86400 * 2);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        uint256 deposits = BaseFarm(lockupFarm).totalDeposits();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).claimRewards(deposits + 1);
    }

    function test_claimRewards_lockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        skip(86400 * 15);
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(currentActor, 1);

        vm.expectEmit(true, true, true, false); // Not checking the rewards claimed here
        emit RewardsClaimed(1, rewardsForEachSubs);
        BaseFarm(lockupFarm).claimRewards(1);
        // Checking the rewards claimed users balences
        for (uint8 i; i < rewardTokens.length; ++i) {
            assertEq(IERC20(rewardTokens[i]).balanceOf(currentActor), rewardsForEachSubs[0][i] + balances[i]);
        }
    }

    function test_claimRewards_nonLockupFarm() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        skip(86400 * 15);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, 1);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(1, rewardsForEachSubs);
        BaseFarm(nonLockupFarm).claimRewards(1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            assertEq(IERC20(rewardTokens[i]).balanceOf(currentActor), rewardsForEachSubs[0][i] + balances[i]);
        }
    }

    function test_claimRewards_max_rewards() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 time;
        uint256 rwdRate = 1e16;
        uint256 rwdBalance = BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        time = rwdBalance / rwdRate; //Max time to be skipped for claiming max reward
        skip(time + 100); //skip more than the available reward
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, 1);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(1, rewardsForEachSubs);
        BaseFarm(nonLockupFarm).claimRewards(1);
    }
}

abstract contract WithdrawTest is BaseFarmTest {
    function test_withdraw_lockupFarm_RevertsWhen_PleaseInitiateCooldown()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.PleaseInitiateCooldown.selector));
        BaseFarm(lockupFarm).withdraw(1);
    }

    function test_withdraw_lockupFarm_RevertsWhen_DepositIsInCooldown()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        BaseFarm(lockupFarm).initiateCooldown(1);
        skip((COOLDOWN_PERIOD * 86400) - 100); //100 seconds before the end of CoolDown Period
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositIsInCooldown.selector));
        BaseFarm(lockupFarm).withdraw(1);
    }

    function test_withdraw_lockupFarm() public setup {
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        uint256 liquidity = deposit(lockupFarm, true, 1e3);

        assertEq(BaseFarm(lockupFarm).getDeposit(1).liquidity, liquidity);

        vm.startPrank(user);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(lockupFarm).initiateCooldown(1);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        BaseFarm(lockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        vm.expectEmit(true, false, false, true);
        emit PoolUnsubscribed(1, 0, rewardsForEachSubs[0]);
        vm.expectEmit(true, false, false, true);
        emit DepositWithdrawn(1);
        BaseFarm(lockupFarm).withdraw(1);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        vm.stopPrank();
    }

    function test_withdraw_lockupFarm_paused() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 time = 3 days;
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        vm.startPrank(owner);
        skip(time);
        BaseFarm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(lockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(user, 1);
        vm.expectEmit(true, false, false, true);
        emit DepositWithdrawn(1);
        BaseFarm(lockupFarm).withdraw(1);
        vm.stopPrank();
    }

    function test_withdraw_nonLockupFarm() public setup {
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        uint256 liquidity = deposit(nonLockupFarm, false, 1e3);

        assertEq(BaseFarm(nonLockupFarm).getDeposit(1).liquidity, liquidity);

        vm.startPrank(user);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(currentActor, 1);
        vm.expectEmit(true, false, false, true);
        emit PoolUnsubscribed(1, 0, rewardsForEachSubs[0]);
        vm.expectEmit(true, false, false, true);
        emit DepositWithdrawn(1);
        BaseFarm(nonLockupFarm).withdraw(1);
        vm.stopPrank();
    }

    function test_withdraw_nonLockupFarm_paused() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 time = 3 days;
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        vm.startPrank(owner);
        skip(time);
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(user, 1);
        vm.expectEmit(true, false, false, true);
        emit DepositWithdrawn(1);
        BaseFarm(nonLockupFarm).withdraw(1);
        vm.stopPrank();
    }

    function test_withdraw_firstDeposit_lockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory multipleUserDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        BaseFarm.Subscription[] memory multipleUserLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(lockupFarm).getDeposit(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[1]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(lockupFarm).initiateCooldown(1);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        BaseFarm(lockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(actors[1], 1);
        BaseFarm(lockupFarm).withdraw(1);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 1) {
                assertEq(BaseFarm(lockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDeposit(i))),
                    keccak256(abi.encode(multipleUserDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 1))),
                    keccak256(abi.encode(multipleUserLockUpSubscriptions[i - 1]))
                );
            }
        }
    }

    function test_withdraw_inBetweenDeposit_lockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory userDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        BaseFarm.Subscription[] memory multipleUserLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            userDeposits[i - 1] = BaseFarm(lockupFarm).getDeposit(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[5]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(lockupFarm).initiateCooldown(5);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        BaseFarm(lockupFarm).getDeposit(5);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(actors[5], 5);
        BaseFarm(lockupFarm).withdraw(5);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 5) {
                assertEq(BaseFarm(lockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDeposit(i))),
                    keccak256(abi.encode(userDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 1))),
                    keccak256(abi.encode(multipleUserLockUpSubscriptions[i - 1]))
                );
            }
        }
    }

    function test_withdraw_lastDeposit_lockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory multipleUserDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        BaseFarm.Subscription[] memory multipleUserLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(lockupFarm).getDeposit(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[10]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(lockupFarm).initiateCooldown(10);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        BaseFarm(lockupFarm).getDeposit(10);
        rewardsForEachSubs[0] = BaseFarm(lockupFarm).computeRewards(actors[10], 10);
        BaseFarm(lockupFarm).withdraw(10);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 10) {
                assertEq(BaseFarm(lockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDeposit(i))),
                    keccak256(abi.encode(multipleUserDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getSubscriptionInfo(i, 1))),
                    keccak256(abi.encode(multipleUserLockUpSubscriptions[i - 1]))
                );
            }
        }
    }

    function test_withdraw_firstDeposit_nonLockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory multipleUserDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(nonLockupFarm).getDeposit(i);
            // emit log_named_uint("numSubs", BaseFarm(nonLockupFarm).getNumSubscriptions(i));
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[1]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        BaseFarm(nonLockupFarm).getDeposit(1);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(actors[1], 1);
        BaseFarm(nonLockupFarm).withdraw(1);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 1) {
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDeposit(i))),
                    keccak256(abi.encode(multipleUserDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
            }
        }
    }

    function test_withdraw_inBetweenDeposit_nonLockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory userDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            userDeposits[i - 1] = BaseFarm(nonLockupFarm).getDeposit(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[5]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        BaseFarm(nonLockupFarm).getDeposit(5);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(actors[5], 5);
        BaseFarm(nonLockupFarm).withdraw(5);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 5) {
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDeposit(i))),
                    keccak256(abi.encode(userDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
            }
        }
    }

    function test_withdraw_lastDeposit_nonLockupFarm_multipleDeposits() public setup {
        BaseFarm.Deposit[] memory multipleUserDeposits = new BaseFarm.Deposit[](10);
        BaseFarm.Subscription[] memory multipleUserNonLockUpSubscriptions = new BaseFarm.Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(nonLockupFarm).getDeposit(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[10]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        BaseFarm(nonLockupFarm).getDeposit(10);
        rewardsForEachSubs[0] = BaseFarm(nonLockupFarm).computeRewards(actors[10], 10);
        BaseFarm(nonLockupFarm).withdraw(10);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(SPA);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 10) {
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDeposit(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDeposit(i))),
                    keccak256(abi.encode(multipleUserDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
            }
        }
    }
}

abstract contract GetRewardFundInfoTest is BaseFarmTest {
    function test_getRewardFundInfo_LockupFarm_revertsWhen_RewardFundDoesNotExist() public setup useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.RewardFundDoesNotExist.selector));
        BaseFarm(lockupFarm).getRewardFundInfo(2);
    }

    function test_getRewardFundInfo_LockupFarm() public setup useKnownActor(user) {
        BaseFarm(lockupFarm).getRewardFundInfo(0);
    }
}

abstract contract RecoverERC20Test is BaseFarmTest {
    function test_recoverE20_LockupFarm_revertsWhen_CannotWithdrawRewardToken() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawRewardToken.selector));
        BaseFarm(lockupFarm).recoverERC20(USDCe);
    }

    function test_recoverE20_LockupFarm_revertsWhen_CannotWithdrawZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        BaseFarm(lockupFarm).recoverERC20(USDT);
    }

    function testFuzz_recoverE20_LockupFarm(uint256 amt) public useKnownActor(owner) {
        amt = bound(amt, 1000 * 10 ** ERC20(USDT).decimals(), 10000 * 10 ** ERC20(USDT).decimals());
        deal(USDT, address(lockupFarm), 10e10);
        vm.expectEmit(true, true, false, false);
        emit RecoveredERC20(USDT, 10e10);
        BaseFarm(lockupFarm).recoverERC20(USDT);
    }
}

abstract contract InitiateCooldownTest is BaseFarmTest {
    // this check is to make sure someone else other than the depositor cannot initiate cooldown
    function test_initiateCooldown_LockupFarm_revertsWhen_DepositDoesNotExist()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(actors[9])
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).initiateCooldown(1);
    }

    function test_initiateCooldown_LockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        BaseFarm.Deposit memory userDeposit = BaseFarm(lockupFarm).getDeposit(1);
        skip(86400 * 7);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        vm.expectEmit(true, false, false, false);
        emit RewardsClaimed(1, rewardsForEachSubs); // not checking the rewardsForEachSubs data here
        vm.expectEmit(true, false, false, false);
        emit PoolUnsubscribed(1, 1, rewardsForEachSubs[0]); // not checking the totalRewardsClaimed data here
        vm.expectEmit(true, true, false, true);
        emit CooldownInitiated(1, userDeposit.startTime + ((COOLDOWN_PERIOD + 7) * 86400));
        BaseFarm(lockupFarm).initiateCooldown(1);
    }

    function test_initiateCooldown_nonLockupFarm()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(86400 * 7);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotInitiateCooldown.selector));
        BaseFarm(nonLockupFarm).initiateCooldown(1);
    }
}

abstract contract AddRewardsTest is BaseFarmTest {
    function test_addRewards_nonLockupFarm_revertsWhen_InvalidRewardToken() public useKnownActor(owner) {
        uint256 rwdAmt = 1 * 10 ** ERC20(invalidRewardToken).decimals();
        deal(address(invalidRewardToken), currentActor, rwdAmt);
        ERC20(invalidRewardToken).approve(nonLockupFarm, rwdAmt);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardToken.selector));
        BaseFarm(nonLockupFarm).addRewards(invalidRewardToken, rwdAmt);
    }

    function test_addRewards_lockupFarm_revertsWhen_ZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.ZeroAmount.selector));
        BaseFarm(lockupFarm).addRewards(USDCe, 0);
    }

    function testFuzz_addRewards_nonLockupFarm(uint256 rwdAmt) public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            rwdAmt = bound(
                rwdAmt,
                1000 * 10 ** ERC20(rewardTokens[i]).decimals(),
                1000000 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            deal(address(rewardTokens[i]), currentActor, rwdAmt);
            ERC20(rewardTokens[i]).approve(nonLockupFarm, rwdAmt);
            vm.expectEmit(true, true, false, true);
            emit RewardAdded(rewardTokens[i], rwdAmt);
            BaseFarm(nonLockupFarm).addRewards(rewardTokens[i], rwdAmt);
            assertEq(BaseFarm(nonLockupFarm).getRewardBalance(rewardTokens[i]), rwdAmt);
        }
    }

    function testFuzz_addRewards_lockupFarm(uint256 rwdAmt) public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            rwdAmt = bound(rwdAmt, 1000 * 10 ** decimals, 10000 * 10 ** decimals);
            deal(address(rewardTokens[i]), currentActor, rwdAmt);
            ERC20(rewardTokens[i]).approve(address(lockupFarm), rwdAmt);
            vm.expectEmit(true, true, false, true);
            emit RewardAdded(rewardTokens[i], rwdAmt);
            BaseFarm(lockupFarm).addRewards(rewardTokens[i], rwdAmt);
            assertEq(BaseFarm(lockupFarm).getRewardBalance(rewardTokens[i]), rwdAmt);
        }
    }
}

abstract contract SetRewardRateTest is BaseFarmTest {
    function testFuzz_setRewardRate_nonLockupFarm_revertsWhen_farmIsClosed(uint256 rwdRateNonLockup)
        public
        useKnownActor(owner)
    {
        uint256[] memory rwdRate = new uint256[](1);
        rwdRate[0] = rwdRateNonLockup;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
        }
        vm.startPrank(owner);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).setRewardRate(rewardTokens[0], rwdRate);
    }

    function testFuzz_setRewardRate_noLockupFarm_revertsWhen_InvalidRewardRatesLength(uint256 rwdRateNonLockup)
        public
        useKnownActor(owner)
    {
        uint256[] memory rwdRate = new uint256[](1);
        rwdRate[0] = rwdRateNonLockup;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }

            vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardRatesLength.selector));

            BaseFarm(lockupFarm).setRewardRate(rewardTokens[i], rwdRate);
        }
    }

    function testFuzz_setRewardRate_noLockupFarm(uint256 rwdRateNonLockup) public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](1);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            rwdRate[0] = rwdRateNonLockup;
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }

            vm.expectEmit(false, false, false, true);
            emit RewardRateUpdated(rewardTokens[i], rwdRate);
            BaseFarm(nonLockupFarm).setRewardRate(rewardTokens[i], rwdRate);

            assertEq(BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]), rwdRate);
        }
    }

    function testFuzz_setRewardRate_LockupFarm(uint256 rwdRateNonLockup, uint256 rwdRateLockup)
        public
        useKnownActor(owner)
    {
        uint256[] memory rwdRate = new uint256[](2);
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        uint256[] memory oldRewardRate = new uint256[](2);
        for (uint8 i; i < rewardTokens.length; ++i) {
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(
                rwdRateNonLockup,
                1 * 10 ** ERC20(rewardTokens[i]).decimals(),
                2 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            rwdRateLockup = bound(
                rwdRateLockup, 2 * 10 ** ERC20(rewardTokens[i]).decimals(), 4 * 10 ** ERC20(rewardTokens[i]).decimals()
            );
            rwdRate[0] = rwdRateNonLockup;
            rwdRate[1] = rwdRateLockup;
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }

            vm.expectEmit(false, false, false, true);
            emit RewardRateUpdated(rewardTokens[i], rwdRate);
            BaseFarm(lockupFarm).setRewardRate(rewardTokens[i], rwdRate);
            assertEq(BaseFarm(lockupFarm).getRewardRates(rewardTokens[i]), rwdRate);
        }
    }
}

abstract contract GetRewardBalanceTest is BaseFarmTest {
    function test_rewardBalance_invalidRwdTkn() public setup depositSetup(lockupFarm, true) useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardToken.selector));
        BaseFarm(nonLockupFarm).getRewardBalance(invalidRewardToken);
    }

    function test_rewardBalance_nonLockupFarm() public setup depositSetup(nonLockupFarm, false) useKnownActor(owner) {
        for (uint8 i = 0; i < rwdTokens.length; ++i) {
            uint256 rwdBalance = BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[i]);
            assert(rwdBalance != 0);
        }
    }

    function test_rewardBalance_lockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(owner) {
        for (uint8 i = 0; i < rwdTokens.length; ++i) {
            uint256 rwdBalance = BaseFarm(lockupFarm).getRewardBalance(BaseFarm(lockupFarm).rewardTokens(i));
            assert(rwdBalance != 0);
        }
    }
}

abstract contract GetDepositTest is BaseFarmTest {
    function test_getInvalidDeposit_nonLockupFarm()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getDeposit(0);

        uint256 totalDeposits = BaseFarm(nonLockupFarm).totalDeposits();

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getDeposit(totalDeposits + 1);
    }

    function test_getInvalidDeposit_lockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).getDeposit(0);

        uint256 totalDeposits = BaseFarm(lockupFarm).totalDeposits();

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).getDeposit(totalDeposits + 1);
    }
}

abstract contract GetNumSubscriptionsTest is BaseFarmTest {
    function test_getDeposit_nonLockupFarm() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 numSubscriptions = BaseFarm(nonLockupFarm).getNumSubscriptions(0);
        assertEq(numSubscriptions, 0);
    }

    function test_getDeposit_lockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 numSubscriptions = BaseFarm(lockupFarm).getNumSubscriptions(0);
        assertEq(numSubscriptions, 0);
    }
}

abstract contract SubscriptionInfoTest is BaseFarmTest {
    function test_subInfo_revertsWhen_SubscriptionDoesNotExist()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getSubscriptionInfo(1, 2);
    }

    function test_subInfo_nonLockupFarm() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        BaseFarm.Subscription memory numSubscriptions = BaseFarm(nonLockupFarm).getSubscriptionInfo(1, 0);
        assertEq(numSubscriptions.fundId, 0);
    }

    function test_subInfo_lockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        BaseFarm.Subscription memory numSubscriptions = BaseFarm(lockupFarm).getSubscriptionInfo(1, 0);
        assertEq(numSubscriptions.fundId, 0);
    }
}

abstract contract UpdateTokenManagerTest is BaseFarmTest {
    function test_updateTknManager_nonLockupFarm_revertsWhen_FarmIsClosed() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;

        vm.startPrank(owner);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).updateTokenManager(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager_nonLockupFarm_revertsWhen_NotTheTokenManager() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.NotTheTokenManager.selector));
        BaseFarm(nonLockupFarm).updateTokenManager(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager_nonLockupFarm_revertsWhen_InvalidAddress()
        public
        useKnownActor(SPA_REWARD_MANAGER)
    {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = address(0);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidAddress.selector));
        BaseFarm(nonLockupFarm).updateTokenManager(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager_nonLockupFarm() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;
        address sender;
        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            if (rewardTokens[i] == SPA) {
                sender = SPA_REWARD_MANAGER;
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                sender = currentActor;
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, false, false, true);
            emit TokenManagerUpdated(rwdToken, _newTknManager);
            BaseFarm(nonLockupFarm).updateTokenManager(rwdToken, _newTknManager);
        }
    }

    function test_updateTknManager_LockupFarm() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);
        address _newTknManager = newTokenManager;
        address sender;
        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            if (rewardTokens[i] == SPA) {
                sender = SPA_REWARD_MANAGER;
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                sender = currentActor;
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, false, false, true);
            emit TokenManagerUpdated(rwdToken, _newTknManager);
            BaseFarm(lockupFarm).updateTokenManager(rwdToken, _newTknManager);
        }
    }
}

abstract contract RecoverRewardFundsTest is BaseFarmTest {
    function test_recoverRewardFund_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            uint256 rwdBalance = ERC20(rwdToken).balanceOf(nonLockupFarm);
            address sender;

            if (rwdToken == SPA) {
                sender = SPA_REWARD_MANAGER;
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                sender = currentActor;
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, true, false, true);
            emit FundsRecovered(sender, rwdToken, rwdBalance);
            BaseFarm(nonLockupFarm).recoverRewardFunds(rwdToken, rwdBalance);
        }
    }

    function test_recoverRewardFund_lockupFarm() public setup useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            deal(rwdToken, lockupFarm, 1e3);
            uint256 rwdBalance = ERC20(rwdToken).balanceOf(lockupFarm);
            address sender;

            if (rwdToken == SPA) {
                sender = SPA_REWARD_MANAGER;
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                sender = currentActor;
                vm.startPrank(currentActor);
            }
            vm.expectEmit(true, true, false, true);
            emit FundsRecovered(sender, rwdToken, rwdBalance);
            BaseFarm(lockupFarm).recoverRewardFunds(rwdToken, rwdBalance);
        }
    }

    function test_recoverRewardFund_lockupFarm_partially() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(lockupFarm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            deal(rwdToken, lockupFarm, 6e6);
            uint256 rwdToRecover = 5e6;
            address sender;
            uint256 rwdBalanceBefore = ERC20(rwdToken).balanceOf(lockupFarm);

            if (rwdToken == SPA) {
                sender = SPA_REWARD_MANAGER;
                vm.startPrank(SPA_REWARD_MANAGER);
            } else {
                sender = currentActor;
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, true, false, true);
            emit FundsRecovered(sender, rwdToken, rwdToRecover);
            BaseFarm(lockupFarm).recoverRewardFunds(rwdToken, rwdToRecover);

            uint256 rwdBalanceAfter = ERC20(rwdToken).balanceOf(lockupFarm);
            assertEq(rwdBalanceAfter, rwdBalanceBefore - rwdToRecover);
        }
    }
}

abstract contract FarmPauseSwitchTest is BaseFarmTest {
    function test_farmPause_noLockupFarm_revertsWhen_FarmAlreadyInRequiredState(bool _isPaused)
        public
        useKnownActor(owner)
    {
        bool isPaused = BaseFarm(nonLockupFarm).isPaused();
        vm.assume(_isPaused == isPaused);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyInRequiredState.selector));
        BaseFarm(nonLockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_lockupFarm_revertsWhen_FarmAlreadyInRequiredState(bool _isPaused)
        public
        useKnownActor(owner)
    {
        bool isPaused = BaseFarm(lockupFarm).isPaused();
        vm.assume(_isPaused == isPaused);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyInRequiredState.selector));
        BaseFarm(lockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_noLockupFarm_revertsWhen_FarmIsClosed(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarm(nonLockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_lockupFarm_revertsWhen_FarmIsClosed(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarm(lockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(lockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_noLockupFarm(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarm(nonLockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        vm.expectEmit(true, true, false, true);
        emit FarmPaused(_isPaused);
        BaseFarm(nonLockupFarm).farmPauseSwitch(_isPaused);
    }

    function test_farmPause_lockupFarm(bool _isPaused) public useKnownActor(owner) {
        bool isPaused = BaseFarm(lockupFarm).isPaused();
        vm.assume(_isPaused != isPaused);
        vm.expectEmit(true, true, false, true);
        emit FarmPaused(_isPaused);
        BaseFarm(lockupFarm).farmPauseSwitch(_isPaused);
    }
}

abstract contract UpdateFarmStartTimeTest is BaseFarmTest {
    function test_start_time_noLockupFarm_revertsWhen_FarmAlreadyStarted() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyStarted.selector));
        BaseFarm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_start_time_lockupFarm_revertsWhen_FarmAlreadyStarted() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyStarted.selector));
        BaseFarm(lockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_start_time_noLockupFarm_revertsWhen_InvalidTime() public {
        address farm = createFarm(block.timestamp + 2000, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidTime.selector));
        BaseFarm(farm).updateFarmStartTime(block.timestamp - 1);
    }

    function test_start_time_lockupFarm_revertsWhen_InvalidTime() public {
        address farm = createFarm(block.timestamp + 200, true);
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidTime.selector));
        BaseFarm(farm).updateFarmStartTime(block.timestamp - 1);
    }

    function test_start_time_noLockupFarm(uint256 farmStartTime, uint256 newStartTime) public {
        vm.assume(farmStartTime > block.timestamp + 2 && newStartTime == farmStartTime - 1);
        address farm = createFarm(farmStartTime, false);
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarm(farm).updateFarmStartTime(newStartTime);
    }

    function test_start_time_lockupFarm(uint256 farmStartTime, uint256 newStartTime) public {
        vm.assume(farmStartTime > block.timestamp + 2 && newStartTime == farmStartTime - 1);

        address farm = createFarm(farmStartTime, true);
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarm(farm).updateFarmStartTime(newStartTime);
    }
}

abstract contract UpdateCoolDownPeriodTest is BaseFarmTest {
    function testFuzz_updateCoolDown_noLockupFarm(uint256 cooldownPeriod) public useKnownActor(owner) {
        cooldownPeriod = bound(cooldownPeriod, 1, 30);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmDoesNotSupportLockup.selector));
        BaseFarm(nonLockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function testFuzz_updateCoolDown_noLockupFarm_revertsWhen_FarmIsClosed(uint256 cooldownPeriod)
        public
        useKnownActor(owner)
    {
        cooldownPeriod = bound(cooldownPeriod, 1, 30);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_updateCoolDown_lockupFarm_revertsWhen_InvalidCooldownPeriod(uint256 cooldownPeriod)
        public
        useKnownActor(owner)
    {
        vm.assume(cooldownPeriod > 30 && cooldownPeriod < 720);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidCooldownPeriod.selector));
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_updateCoolDown_lockupFarm_revertsWhen_InvalidCooldownPeriod0(uint256 cooldownPeriod)
        public
        useKnownActor(owner)
    {
        vm.assume(cooldownPeriod == 0);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidCooldownPeriod.selector));
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_updateCoolDown_lockupFarm(uint256 cooldownPeriod) public useKnownActor(owner) {
        vm.assume(cooldownPeriod > 0 && cooldownPeriod < 31);

        vm.expectEmit(true, true, false, true);
        emit CooldownPeriodUpdated(cooldownPeriod);
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }
}

abstract contract _SetupFarmTest is BaseFarmTest {
    function test_revertWhen_InvalidFarmStartTime() public {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidFarmStartTime.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp - 200, false));
        assertTrue(success);
    }

    function test_revertWhen_InvalidRewardData() public {
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardData.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }

    function test_revertWhen_RewardAlreadyAdded() public {
        rwdTokens.push(SPA);

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.RewardTokenAlreadyAdded.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }
}

abstract contract MulticallTest is BaseFarmTest {
    function test_Multicall(uint256 cooldownPeriod) public useKnownActor(owner) {
        cooldownPeriod = bound(cooldownPeriod, 1, 30);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(BaseFarm.updateCooldownPeriod.selector, cooldownPeriod);
        data[1] = abi.encodeWithSelector(BaseFarm.closeFarm.selector);

        BaseFarm(lockupFarm).multicall(data);

        assertEq(BaseFarm(lockupFarm).cooldownPeriod(), cooldownPeriod);
        assertEq(BaseFarm(lockupFarm).isClosed(), true);
    }

    function test_revertWhen_AnyIndividualTestFail(uint256 cooldownPeriod) public useKnownActor(owner) {
        // when any multiple calls fail
        {
            bytes[] memory data = new bytes[](1);
            // This should revert as farm already started.
            data[0] = abi.encodeWithSelector(BaseFarm.updateFarmStartTime.selector, block.timestamp + 200);

            vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyStarted.selector));
            BaseFarm(lockupFarm).multicall(data);
        }

        // when one of multiple calls fail
        {
            cooldownPeriod = bound(cooldownPeriod, 1, 30);

            // When any single call fails the whole transaction should revert.
            bytes[] memory data = new bytes[](3);
            data[0] = abi.encodeWithSelector(BaseFarm.updateCooldownPeriod.selector, cooldownPeriod);
            // This should revert as farm already started.
            data[1] = abi.encodeWithSelector(BaseFarm.updateFarmStartTime.selector, block.timestamp + 200);
            data[2] = abi.encodeWithSelector(BaseFarm.closeFarm.selector);

            vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyStarted.selector));
            BaseFarm(lockupFarm).multicall(data);
        }

        // checking sender
        {
            changePrank(user);
            cooldownPeriod = bound(cooldownPeriod, 1, 30);

            // When any single call fails the whole transaction should revert.
            bytes[] memory data = new bytes[](3);
            data[0] = abi.encodeWithSelector(BaseFarm.updateCooldownPeriod.selector, cooldownPeriod);

            vm.expectRevert("Ownable: caller is not the owner");
            BaseFarm(lockupFarm).multicall(data);
        }
    }

    function test_revertWhen_CallInternalFunction() public useKnownActor(owner) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("_updateFarmRewardData()");

        vm.expectRevert("Address: low-level delegate call failed");
        BaseFarm(lockupFarm).multicall(data);
    }
}
