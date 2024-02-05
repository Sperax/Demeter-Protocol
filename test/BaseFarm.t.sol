// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarm, RewardTokenData} from "../contracts/BaseFarm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {Deposit, Subscription, RewardData, RewardFund} from "../contracts/interfaces/DataTypes.sol";

abstract contract BaseFarmTest is TestNetworkConfig {
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
    event RewardDataUpdated(address indexed rwdToken, address newTokenManager);
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

    function _depositSetup(address farm, bool lockup) public {
        addRewards(farm);
        setRewardRates(farm);
        deposit(farm, lockup, 1e3);
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

                vm.startPrank(owner);
                BaseFarm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        } else {
            uint256[] memory rwdRate = new uint256[](1);
            address[] memory farmRewardTokens = getRewardTokens(farm);
            for (uint8 i; i < farmRewardTokens.length; ++i) {
                rwdRate[0] = 1 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.01
                vm.startPrank(owner);
                BaseFarm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        }
    }

    function createFarm(uint256 startTime, bool lockup) public virtual returns (address);

    function deposit(address farm, bool locked, uint256 amt) public virtual returns (uint256);

    function deposit(address farm, bool locked, uint256 amt, bytes memory revertMsg) public virtual;

    function getRewardTokens(address farm) public view returns (address[] memory) {
        address[] memory farmRewardTokens = new address[](rwdTokens.length);
        for (uint8 i = 0; i < rwdTokens.length; ++i) {
            farmRewardTokens[i] = BaseFarm(farm).rewardTokens(i);
        }
        return farmRewardTokens;
    }
}

abstract contract DepositTest is BaseFarmTest {
    function test_deposit_RevertWhen_NoLiquidityInPosition() public {
        deposit(nonLockupFarm, false, 0, abi.encodeWithSelector(BaseFarm.NoLiquidityInPosition.selector));
    }

    function test_deposit_RevertWhen_LockupFunctionalityIsDisabled() public {
        deposit(nonLockupFarm, true, 1e2, abi.encodeWithSelector(BaseFarm.LockupFunctionalityIsDisabled.selector));
    }

    function test_deposit_RevertWhen_FarmIsInactive() public {
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        deposit(nonLockupFarm, false, 1e2, abi.encodeWithSelector(BaseFarm.FarmIsInactive.selector));
    }

    function test_deposit_RevertWhen_FarmIsClosed() public {
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).closeFarm();
        deposit(nonLockupFarm, false, 1e2, abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
    }

    function test_deposit_deposit(bool lockup) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        deposit(farm, lockup, 1e2);
    }
}

abstract contract ClaimRewardsTest is BaseFarmTest {
    function test_ClaimRewards_RevertWhen_FarmIsClosed()
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
        skip(86400 * 2);
        vm.startPrank(owner);
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(lockupFarm).claimRewards(1);
    }

    function test_ClaimRewards_RevertWhen_DepositDoesNotExist()
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
        uint256 deposits = BaseFarm(lockupFarm).totalDeposits();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).claimRewards(deposits + 1);
    }

    function test_claimRewards(bool lockup) public setup {
        address farm;
        uint256 rewardsForEachSubsLength;
        farm = lockup ? lockupFarm : nonLockupFarm;
        rewardsForEachSubsLength = lockup ? 2 : 1;
        _depositSetup(farm, lockup);
        skip(86400 * 15);
        vm.startPrank(user);
        address[] memory rewardTokens = getRewardTokens(farm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(user);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](rewardsForEachSubsLength);
        rewardsForEachSubs = BaseFarm(farm).computeRewards(user, 1);

        vm.expectEmit(address(farm));
        emit RewardsClaimed(1, rewardsForEachSubs);
        BaseFarm(farm).claimRewards(1);
        // Checking the rewards claimed users balences
        for (uint8 i; i < rewardTokens.length; ++i) {
            if (lockup) {
                assertEq(
                    IERC20(rewardTokens[i]).balanceOf(user),
                    rewardsForEachSubs[0][i] + rewardsForEachSubs[1][i] + balances[i]
                );
            } else {
                assertEq(IERC20(rewardTokens[i]).balanceOf(user), rewardsForEachSubs[0][i] + balances[i]);
            }
        }
    }

    function test_claimRewards_max_rewards() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 time;
        uint256 rwdRate = 1e19;
        uint256 rwdBalance = BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        // for testing purpose, reward rate is set in a way that we can claim max rewards before farm expiry.
        time = rwdBalance / rwdRate; //Max time to be skipped for claiming max reward
        skip(time + 100); //skip more than the available reward
        rewardsForEachSubs = BaseFarm(nonLockupFarm).computeRewards(currentActor, 1);

        vm.expectEmit(address(nonLockupFarm));
        emit RewardsClaimed(1, rewardsForEachSubs);
        BaseFarm(nonLockupFarm).claimRewards(1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            assertEq(IERC20(rewardTokens[i]).balanceOf(currentActor), rewardsForEachSubs[0][i] + balances[i]);
        }
    }

    function test_claimRewards_rwd_rate_0() public setup depositSetup(nonLockupFarm, false) {
        uint256 time = 15 days;
        uint256 depositId = 1;
        uint256[] memory rwdRate = new uint256[](1);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        rwdRate[0] = 0;
        vm.startPrank(owner);
        BaseFarm(nonLockupFarm).setRewardRate(rwdTokens[0], rwdRate);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs = BaseFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(nonLockupFarm));
        emit RewardsClaimed(depositId, rewardsForEachSubs);
        BaseFarm(nonLockupFarm).claimRewards(depositId);
        assertEq(rewardsForEachSubs[0][0], 0);
        for (uint8 i; i < rewardTokens.length; ++i) {
            assertEq(IERC20(rewardTokens[i]).balanceOf(currentActor), rewardsForEachSubs[0][i] + balances[i]);
        }
    }
}

abstract contract WithdrawTest is BaseFarmTest {
    function test_withdraw_lockupFarm_RevertWhen_PleaseInitiateCooldown()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.PleaseInitiateCooldown.selector));
        BaseFarm(lockupFarm).withdraw(1);
    }

    function test_withdraw_lockupFarm_RevertWhen_DepositIsInCooldown()
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

    function test_withdraw_lockupFarm_paused() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        uint256 time = 3 days;
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.startPrank(owner);
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        rewardsForEachSubs = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        BaseFarm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        vm.expectEmit(address(lockupFarm));
        emit PoolUnsubscribed(depositId, 0, rewardsForEachSubs[0]);
        vm.expectEmit(address(lockupFarm));
        emit PoolUnsubscribed(depositId, 1, rewardsForEachSubs[1]);
        vm.expectEmit(address(lockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(lockupFarm).withdraw(depositId);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_lockupFarm_closed() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        uint256 time = 3 days;
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.startPrank(owner);
        skip(time);
        BaseFarm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectEmit(address(lockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(lockupFarm).withdraw(depositId);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_lockupFarm() public setup {
        uint256 depositId = 1;
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        uint256 liquidity = deposit(lockupFarm, true, 1e3);

        assertEq(BaseFarm(lockupFarm).getDepositInfo(1).liquidity, liquidity);

        vm.startPrank(user);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        BaseFarm(lockupFarm).initiateCooldown(depositId);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(lockupFarm).getDepositInfo(depositId);
        rewardsForEachSubs = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        vm.expectEmit(address(lockupFarm));
        emit PoolUnsubscribed(depositId, 0, rewardsForEachSubs[0]);
        vm.expectEmit(address(lockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(lockupFarm).withdraw(depositId);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(lockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_nonLockupFarm() public setup {
        uint256 depositId = 1;
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        uint256 liquidity = deposit(nonLockupFarm, false, 1e3);

        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(1).liquidity, liquidity);

        vm.startPrank(user);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        BaseFarm(nonLockupFarm).getDepositInfo(depositId);
        rewardsForEachSubs = BaseFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(nonLockupFarm));
        emit PoolUnsubscribed(depositId, 0, rewardsForEachSubs[0]);
        vm.expectEmit(address(nonLockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(nonLockupFarm).withdraw(depositId);
        vm.stopPrank();
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_nonLockupFarm_paused() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256 time = 3 days;
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        vm.startPrank(owner);
        skip(time);
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        vm.expectEmit(address(nonLockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(nonLockupFarm).withdraw(depositId);
        vm.stopPrank();
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_nonLockupFarm_closed() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256 time = 3 days;
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        vm.startPrank(owner);
        skip(time);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectEmit(address(nonLockupFarm));
        emit DepositWithdrawn(depositId);
        BaseFarm(nonLockupFarm).withdraw(depositId);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).depositor, address(0));
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).liquidity, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).startTime, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).expiryDate, 0);
        assertEq(BaseFarm(nonLockupFarm).getDepositInfo(depositId).cooldownPeriod, 0);
    }

    function test_withdraw_firstDeposit_lockupFarm_multipleDeposits() public setup {
        Deposit[] memory multipleUserDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        Subscription[] memory multipleUserLockUpSubscriptions = new Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(lockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[1]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        BaseFarm(lockupFarm).initiateCooldown(1);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(lockupFarm).getDepositInfo(1);
        BaseFarm(lockupFarm).withdraw(1);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 1) {
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDepositInfo(i))),
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
        Deposit[] memory userDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        Subscription[] memory multipleUserLockUpSubscriptions = new Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            userDeposits[i - 1] = BaseFarm(lockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[5]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        BaseFarm(lockupFarm).initiateCooldown(5);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(lockupFarm).getDepositInfo(5);
        BaseFarm(lockupFarm).withdraw(5);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 5) {
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDepositInfo(i))),
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
        Deposit[] memory multipleUserDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        Subscription[] memory multipleUserLockUpSubscriptions = new Subscription[](10);
        addRewards(lockupFarm);
        setRewardRates(lockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(lockupFarm, true, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(lockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
            multipleUserLockUpSubscriptions[i - 1] = BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
        }

        vm.startPrank(actors[10]);
        uint256 time = 2 days;
        uint256 cooldownTime = (COOLDOWN_PERIOD * 86400) + 100;
        BaseFarm(lockupFarm).initiateCooldown(10);
        skip(cooldownTime); //100 seconds after the end of CoolDown Period
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(lockupFarm).getDepositInfo(10);
        BaseFarm(lockupFarm).withdraw(10);
        skip(time);
        BaseFarm(lockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 10) {
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(lockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 0);
                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(lockupFarm).getSubscriptionInfo(i, 1);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(lockupFarm).getDepositInfo(i))),
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
        Deposit[] memory multipleUserDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(nonLockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[1]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(nonLockupFarm).getDepositInfo(1);
        BaseFarm(nonLockupFarm).withdraw(1);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 1) {
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDepositInfo(i))),
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
        Deposit[] memory userDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            userDeposits[i - 1] = BaseFarm(nonLockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[5]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(nonLockupFarm).getDepositInfo(5);
        BaseFarm(nonLockupFarm).withdraw(5);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 5) {
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDepositInfo(i))),
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
        Deposit[] memory multipleUserDeposits = new Deposit[](10);
        Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
        addRewards(nonLockupFarm);
        setRewardRates(nonLockupFarm);
        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            deposit(nonLockupFarm, false, i * 1e3);
            multipleUserDeposits[i - 1] = BaseFarm(nonLockupFarm).getDepositInfo(i);
            multipleUserNonLockUpSubscriptions[i - 1] = BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
        }

        vm.startPrank(actors[10]);
        uint256 time = COOLDOWN_PERIOD * 86400 + 100;
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        BaseFarm(nonLockupFarm).getDepositInfo(10);
        BaseFarm(nonLockupFarm).withdraw(10);
        skip(time);
        BaseFarm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        vm.stopPrank();

        for (uint256 i = 1; i <= 10; i++) {
            user = actors[i];
            if (i == 10) {
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).depositor, address(0));
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).liquidity, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).startTime, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).expiryDate, 0);
                assertEq(BaseFarm(nonLockupFarm).getDepositInfo(i).cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
                BaseFarm(nonLockupFarm).getSubscriptionInfo(i, 0);
            } else {
                assertEq(
                    keccak256(abi.encode(BaseFarm(nonLockupFarm).getDepositInfo(i))),
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
    function test_getRewardFundInfo_LockupFarm_RevertWhen_RewardFundDoesNotExist() public setup useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.RewardFundDoesNotExist.selector));
        BaseFarm(lockupFarm).getRewardFundInfo(2);
    }

    function test_getRewardFundInfo_LockupFarm() public setup useKnownActor(user) {
        BaseFarm(lockupFarm).getRewardFundInfo(0);
    }
}

abstract contract RecoverERC20Test is BaseFarmTest {
    function test_recoverE20_LockupFarm_RevertWhen_CannotWithdrawRewardToken() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawRewardToken.selector));
        BaseFarm(lockupFarm).recoverERC20(rwdTokens[0]);
    }

    function test_recoverE20_LockupFarm_RevertWhen_CannotWithdrawZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        BaseFarm(lockupFarm).recoverERC20(USDT);
    }

    function testFuzz_recoverE20_LockupFarm(bool lockup, uint256 amt) public useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        amt = bound(amt, 1000 * 10 ** ERC20(USDT).decimals(), 10000 * 10 ** ERC20(USDT).decimals());
        deal(USDT, address(farm), 10e10);
        vm.expectEmit(address(farm));
        emit RecoveredERC20(USDT, 10e10);
        BaseFarm(farm).recoverERC20(USDT);
    }
}

abstract contract InitiateCooldownTest is BaseFarmTest {
    // this check is to make sure someone else other than the depositor cannot initiate cooldown
    function test_initiateCooldown_LockupFarm_RevertWhen_DepositDoesNotExist()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(actors[9])
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(lockupFarm).initiateCooldown(1);
    }

    function test_initiateCooldown_LockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        Deposit memory userDeposit = BaseFarm(lockupFarm).getDepositInfo(1);
        skip(86400 * 7);
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        rewardsForEachSubs = BaseFarm(lockupFarm).computeRewards(currentActor, 1);
        vm.expectEmit(address(lockupFarm));
        emit RewardsClaimed(1, rewardsForEachSubs);
        vm.expectEmit(address(lockupFarm));
        emit PoolUnsubscribed(1, 1, rewardsForEachSubs[1]);
        vm.expectEmit(address(lockupFarm));
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
    function test_addRewards_nonLockupFarm_RevertWhen_InvalidRewardToken() public useKnownActor(owner) {
        uint256 rwdAmt = 1 * 10 ** ERC20(invalidRewardToken).decimals();
        deal(address(invalidRewardToken), currentActor, rwdAmt);
        ERC20(invalidRewardToken).approve(nonLockupFarm, rwdAmt);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardToken.selector));
        BaseFarm(nonLockupFarm).addRewards(invalidRewardToken, rwdAmt);
    }

    function test_addRewards_lockupFarm_RevertWhen_ZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.ZeroAmount.selector));
        BaseFarm(lockupFarm).addRewards(USDCe, 0);
    }

    function testFuzz_addRewards(bool lockup, uint256 rwdAmt) public useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        address[] memory rewardTokens = getRewardTokens(farm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            rwdAmt = bound(rwdAmt, 1000 * 10 ** decimals, 10000 * 10 ** decimals);
            deal(address(rewardTokens[i]), currentActor, rwdAmt);
            ERC20(rewardTokens[i]).approve(address(farm), rwdAmt);
            vm.expectEmit(address(farm));
            emit RewardAdded(rewardTokens[i], rwdAmt);
            BaseFarm(farm).addRewards(rewardTokens[i], rwdAmt);
            assertEq(BaseFarm(farm).getRewardBalance(rewardTokens[i]), rwdAmt);
        }
    }
}

abstract contract SetRewardRateTest is BaseFarmTest {
    function testFuzz_RevertWhen_FarmIsClosed(uint256 rwdRateNonLockup) public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](1);
        rwdRate[0] = rwdRateNonLockup;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(rwdRateNonLockup, 1 * 10 ** decimals, 2 * 10 ** decimals);
        }
        vm.startPrank(owner);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).setRewardRate(rewardTokens[0], rwdRate);
    }

    function testFuzz_RevertWhen_InvalidRewardRatesLength(uint256 rwdRateNonLockup) public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](1);
        rwdRate[0] = rwdRateNonLockup;
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory oldRewardRate = new uint256[](1);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            oldRewardRate = BaseFarm(nonLockupFarm).getRewardRates(rewardTokens[i]);
            rwdRateNonLockup = bound(rwdRateNonLockup, 1 * 10 ** decimals, 2 * 10 ** decimals);

            vm.startPrank(currentActor);

            vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardRatesLength.selector));

            BaseFarm(lockupFarm).setRewardRate(rewardTokens[i], rwdRate);
        }
    }

    function testFuzz_setRewardRate(bool lockup, uint256 rwdRateNonLockup, uint256 rwdRateLockup) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        uint256[] memory rwdRate;
        if (lockup) {
            rwdRate = new uint256[](2);
        } else {
            rwdRate = new uint256[](1);
        }
        vm.startPrank(owner);
        address[] memory rewardTokens = getRewardTokens(farm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            rwdRateNonLockup = bound(rwdRateNonLockup, 1 * 10 ** decimals, 2 * 10 ** decimals);
            rwdRate[0] = rwdRateNonLockup;
            if (lockup) {
                rwdRateLockup = bound(rwdRateLockup, 2 * 10 ** decimals, 4 * 10 ** decimals);
                rwdRate[1] = rwdRateLockup;
            }

            vm.startPrank(currentActor);

            vm.expectEmit(address(farm));
            emit RewardRateUpdated(rewardTokens[i], rwdRate);
            BaseFarm(farm).setRewardRate(rewardTokens[i], rwdRate);
            assertEq(BaseFarm(farm).getRewardRates(rewardTokens[i]), rwdRate);
        }
    }
}

abstract contract GetRewardBalanceTest is BaseFarmTest {
    function test_RevertWhen_InvalidRewardToken() public setup depositSetup(lockupFarm, true) useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardToken.selector));
        BaseFarm(nonLockupFarm).getRewardBalance(invalidRewardToken);
    }

    function test_rewardBalance(bool lockup) public setup {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        _depositSetup(farm, lockup);
        for (uint8 i = 0; i < rwdTokens.length; ++i) {
            uint256 rwdBalance = BaseFarm(farm).getRewardBalance(rwdTokens[i]);
            assert(rwdBalance != 0);
        }
    }
}

abstract contract GetDepositTest is BaseFarmTest {
    function test_GetDeposit_RevertWhen_DepositDoesNotExist() public setup {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getDepositInfo(0);

        uint256 totalDeposits = BaseFarm(nonLockupFarm).totalDeposits();

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getDepositInfo(totalDeposits + 1);
    }
}

abstract contract GetNumSubscriptionsTest is BaseFarmTest {
    function test_getDeposit(bool lockup) public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        uint256 numSubscriptions = BaseFarm(farm).getNumSubscriptions(0);
        assertEq(numSubscriptions, 0);
    }
}

abstract contract SubscriptionInfoTest is BaseFarmTest {
    function test_RevertWhen_SubscriptionDoesNotExist()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.SubscriptionDoesNotExist.selector));
        BaseFarm(nonLockupFarm).getSubscriptionInfo(1, 2);
    }

    function test_subInfo(bool lockup) public setup {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        _depositSetup(farm, lockup);
        Subscription memory numSubscriptions = BaseFarm(farm).getSubscriptionInfo(1, 0);
        assertEq(numSubscriptions.fundId, 0);
    }
}

abstract contract UpdateRewardTokenDataTest is BaseFarmTest {
    function test_UpdateRewardTokenData_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;

        vm.startPrank(owner);
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_RevertWhen_NotTheTokenManager() public useKnownActor(user) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.NotTheTokenManager.selector));
        BaseFarm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_RevertWhen_InvalidAddress() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = address(0);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidAddress.selector));
        BaseFarm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager(bool lockup) public useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        address[] memory rewardTokens = getRewardTokens(farm);
        address _newTknManager = newTokenManager;
        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];

            vm.expectEmit(address(farm));
            emit RewardDataUpdated(rwdToken, _newTknManager);
            BaseFarm(farm).updateRewardData(rwdToken, _newTknManager);
        }
    }
}

abstract contract RecoverRewardFundsTest is BaseFarmTest {
    function test_recoverRewardFund_one(bool lockup) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        _depositSetup(farm, lockup);
        vm.startPrank(owner);
        address[] memory rewardTokens = getRewardTokens(farm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            uint256 rwdBalance = ERC20(rwdToken).balanceOf(farm);

            vm.expectEmit(address(farm));
            emit FundsRecovered(owner, rwdToken, rwdBalance);
            BaseFarm(farm).recoverRewardFunds(rwdToken, rwdBalance);
        }
    }

    function test_recoverRewardFund_two(bool lockup) public setup useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        address[] memory rewardTokens = getRewardTokens(farm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            deal(rwdToken, farm, 1e3);
            uint256 rwdBalance = ERC20(rwdToken).balanceOf(farm);

            vm.expectEmit(address(farm));
            emit FundsRecovered(currentActor, rwdToken, rwdBalance);
            BaseFarm(farm).recoverRewardFunds(rwdToken, rwdBalance);
        }
    }

    function test_recoverRewardFund_partially(bool lockup) public useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        address[] memory rewardTokens = getRewardTokens(farm);

        for (uint8 i; i < rewardTokens.length; ++i) {
            address rwdToken = rewardTokens[i];
            deal(rwdToken, farm, 6e6);
            uint256 rwdToRecover = 5e6;
            uint256 rwdBalanceBefore = ERC20(rwdToken).balanceOf(farm);

            vm.expectEmit(address(farm));
            emit FundsRecovered(currentActor, rwdToken, rwdToRecover);
            BaseFarm(farm).recoverRewardFunds(rwdToken, rwdToRecover);

            uint256 rwdBalanceAfter = ERC20(rwdToken).balanceOf(farm);
            assertEq(rwdBalanceAfter, rwdBalanceBefore - rwdToRecover);
        }
    }
}

abstract contract FarmPauseSwitchTest is BaseFarmTest {
    function test_RevertWhen_FarmAlreadyInRequiredState() public useKnownActor(owner) {
        bool isFarmActive = BaseFarm(nonLockupFarm).isFarmActive();
        isFarmActive = !isFarmActive;
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyInRequiredState.selector));
        BaseFarm(nonLockupFarm).farmPauseSwitch(isFarmActive);
    }

    function test_FarmPauseSwitch_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        bool isFarmActive = BaseFarm(nonLockupFarm).isFarmActive();
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).farmPauseSwitch(isFarmActive);
    }

    function test_farmPause(bool lockup) public useKnownActor(owner) {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        bool isFarmActive = BaseFarm(farm).isFarmActive();
        vm.expectEmit(address(farm));
        emit FarmPaused(isFarmActive);
        BaseFarm(farm).farmPauseSwitch(isFarmActive);
    }
}

abstract contract UpdateFarmStartTimeTest is BaseFarmTest {
    function test_updateFarmStartTime_revertsWhen_FarmIsClosed() public useKnownActor(owner) {
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_updateFarmStartTime_revertsWhen_FarmAlreadyStarted() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmAlreadyStarted.selector));
        BaseFarm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_updateFarmStartTime_revertsWhen_InvalidTime() public {
        address farm = createFarm(block.timestamp + 2000, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidTime.selector));
        BaseFarm(farm).updateFarmStartTime(block.timestamp - 1);
    }

    function test_updateFarmStartTime(bool lockup, uint256 farmStartTime, uint256 newStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, farmStartTime - 1, type(uint64).max);
        address farm = createFarm(farmStartTime, lockup);

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        BaseFarm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 lastFundUpdateTime = BaseFarm(farm).lastFundUpdateTime();

        assertEq(lastFundUpdateTime, newStartTime);
    }
}

abstract contract UpdateCoolDownPeriodTest is BaseFarmTest {
    function testFuzz_updateCoolDown_noLockupFarm() public useKnownActor(owner) {
        uint256 cooldownPeriod = 20;
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmDoesNotSupportLockup.selector));
        BaseFarm(nonLockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function testFuzz_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        uint256 cooldownPeriod = 20;
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_RevertWhen_InvalidCooldownPeriod(uint256 cooldownPeriod) public useKnownActor(owner) {
        vm.assume(cooldownPeriod > 30 && cooldownPeriod < 720);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidCooldownPeriod.selector));
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_RevertWhen_InvalidCooldownPeriod0(uint256 cooldownPeriod) public useKnownActor(owner) {
        vm.assume(cooldownPeriod == 0);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidCooldownPeriod.selector));
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }

    function test_updateCoolDown_lockupFarm(uint256 cooldownPeriod) public useKnownActor(owner) {
        vm.assume(cooldownPeriod > 0 && cooldownPeriod < 31);

        vm.expectEmit(address(lockupFarm));
        emit CooldownPeriodUpdated(cooldownPeriod);
        BaseFarm(lockupFarm).updateCooldownPeriod(cooldownPeriod);
    }
}

abstract contract CloseFarmTest is BaseFarmTest {
    function test_CloseFarm_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        BaseFarm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseFarm(nonLockupFarm).closeFarm();
    }

    function test_closeFarm_lockupFarm(bool lockup) public useKnownActor(owner) {
        address farm;
        uint256 rewardRateLength;
        farm = lockup ? lockupFarm : nonLockupFarm;
        rewardRateLength = lockup ? 2 : 1;
        address[] memory rewardTokens = getRewardTokens(farm);
        uint256[] memory rwdRate = new uint256[](rewardRateLength);
        vm.expectEmit(address(farm));
        emit FarmClosed();
        BaseFarm(farm).closeFarm();
        assertEq(BaseFarm(farm).isFarmOpen(), false);
        assertEq(BaseFarm(farm).isFarmActive(), false);
        for (uint256 i = 0; i < rwdTokens.length; i++) {
            assertEq(BaseFarm(farm).getRewardRates(rewardTokens[i]), rwdRate);
        }

        // this function also recovers reward funds. Need to test that here.
    }
}

abstract contract _SetupFarmTest is BaseFarmTest {
    function test_RevertWhen_InvalidFarmStartTime() public {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidFarmStartTime.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp - 200, false));
        assertTrue(success);
    }

    function test_RevertWhen_InvalidRewardData() public {
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);
        rwdTokens.push(USDCe);

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.InvalidRewardData.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }

    function test_RevertWhen_RewardAlreadyAdded() public {
        rwdTokens.push(rwdTokens[0]);

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
        assertEq(BaseFarm(lockupFarm).isFarmOpen(), false);
    }

    function test_RevertWhen_AnyIndividualTestFail(uint256 cooldownPeriod) public useKnownActor(owner) {
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

    function test_RevertWhen_CallInternalFunction() public useKnownActor(owner) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("_updateFarmRewardData()");

        vm.expectRevert("Address: low-level delegate call failed");
        BaseFarm(lockupFarm).multicall(data);
    }
}
