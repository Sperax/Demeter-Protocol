// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Farm, RewardTokenData} from "../contracts/Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {Deposit, Subscription, RewardData, RewardFund} from "../contracts/interfaces/DataTypes.sol";

abstract contract FarmTest is TestNetworkConfig {
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    uint8 public constant MAX_NUM_REWARDS = 4;
    uint256 public constant MIN_BALANCE = 1000000000000000000;
    uint256 public constant NO_LOCKUP_REWARD_RATE = 1e18;
    uint256 public constant LOCKUP_REWARD_RATE = 2e18;
    uint256 public constant COOLDOWN_PERIOD_DAYS = 21;
    uint256 public constant MIN_COOLDOWN_PERIOD_DAYS = 1;
    uint256 public constant MAX_COOLDOWN_PERIOD_DAYS = 30;
    bytes32 public constant NO_LOCK_DATA = bytes32(uint256(0));
    bytes32 public constant LOCK_DATA = bytes32(uint256(1));
    uint256 public constant DEPOSIT_AMOUNT = 1e3;
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
        deposit(farm, lockup, DEPOSIT_AMOUNT);
        _;
    }

    function setUp() public virtual override {
        super.setUp();
        user = actors[0];
        newTokenManager = actors[3];
    }

    function depositSetupFn(address farm, bool lockup) public depositSetup(farm, lockup) {}

    function addRewards(address farm) public useKnownActor(owner) {
        address[] memory farmRewardTokens = getRewardTokens(farm);
        uint256 rwdAmt;
        for (uint8 i; i < farmRewardTokens.length; ++i) {
            rwdAmt = 1e7 * 10 ** ERC20(farmRewardTokens[i]).decimals();
            deal(address(farmRewardTokens[i]), owner, rwdAmt);
            ERC20(farmRewardTokens[i]).approve(farm, rwdAmt);
            Farm(farm).addRewards(farmRewardTokens[i], rwdAmt);
        }
    }

    function setRewardRates(address farm) public useKnownActor(owner) {
        if (Farm(farm).cooldownPeriod() != 0) {
            uint256[] memory rwdRate = new uint256[](2);
            address[] memory farmRewardTokens = getRewardTokens(farm);
            for (uint8 i; i < farmRewardTokens.length; ++i) {
                rwdRate[0] = 1 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.01
                rwdRate[1] = 2 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.02
                Farm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        } else {
            uint256[] memory rwdRate = new uint256[](1);
            address[] memory farmRewardTokens = getRewardTokens(farm);
            for (uint8 i; i < farmRewardTokens.length; ++i) {
                rwdRate[0] = 1 * 10 ** ERC20(farmRewardTokens[i]).decimals() / 100; //0.01
                Farm(farm).setRewardRate(farmRewardTokens[i], rwdRate);
            }
        }
    }

    function createFarm(uint256 startTime, bool lockup) public virtual returns (address);

    function deposit(address farm, bool locked, uint256 amt) public virtual returns (uint256);

    function deposit(address farm, bool locked, uint256 amt, bytes memory revertMsg) public virtual;

    function getRewardTokens(address farm) public view returns (address[] memory) {
        return Farm(farm).getRewardTokens();
    }
}

abstract contract DepositTest is FarmTest {
    function test_Deposit_RevertWhen_NoLiquidityInPosition() public {
        deposit(nonLockupFarm, false, 0, abi.encodeWithSelector(Farm.NoLiquidityInPosition.selector));
    }

    function test_Deposit_RevertWhen_LockupFunctionalityIsDisabled() public {
        deposit(nonLockupFarm, true, 1e2, abi.encodeWithSelector(Farm.LockupFunctionalityIsDisabled.selector));
    }

    function test_Deposit_RevertWhen_FarmIsInactive() public {
        vm.startPrank(Farm(nonLockupFarm).owner());
        Farm(nonLockupFarm).farmPauseSwitch(true);
        deposit(nonLockupFarm, false, 1e2, abi.encodeWithSelector(Farm.FarmIsInactive.selector));
    }

    function test_Deposit_RevertWhen_FarmIsClosed() public {
        vm.startPrank(Farm(nonLockupFarm).owner());
        Farm(nonLockupFarm).closeFarm();
        deposit(nonLockupFarm, false, 1e2, abi.encodeWithSelector(Farm.FarmIsClosed.selector));
    }

    function test_deposit() public {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            deposit(farm, lockup, 1e2);
        }
    }
}

abstract contract ClaimRewardsTest is FarmTest {
    function test_ClaimRewards_RevertWhen_FarmIsClosed()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        skip(2 days);
        Farm(lockupFarm).initiateCooldown(depositId);
        vm.startPrank(owner);
        skip(2 days);
        Farm(lockupFarm).farmPauseSwitch(true);
        skip(2 days);
        vm.startPrank(owner);
        Farm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(lockupFarm).claimRewards(depositId);
    }

    function test_ClaimRewards_RevertWhen_DepositDoesNotExist()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        skip(2 days);
        Farm(lockupFarm).initiateCooldown(depositId);
        vm.startPrank(owner);
        skip(2 days);
        Farm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        skip(2 days);
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        Farm(lockupFarm).claimRewards(depositId + 1);
    }

    function test_claimRewards() public setup {
        for (uint8 j; j < 2; ++j) {
            uint256 depositId = 1;
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 rewardsForEachSubsLength = lockup ? 2 : 1;
            depositSetupFn(farm, lockup);
            skip(15 days);
            vm.startPrank(user);
            address[] memory rewardTokens = getRewardTokens(farm);
            uint256[] memory balances = new uint256[](rewardTokens.length);
            for (uint8 i; i < rewardTokens.length; ++i) {
                balances[i] = IERC20(rewardTokens[i]).balanceOf(user);
            }
            uint256[][] memory rewardsForEachSubs = new uint256[][](rewardsForEachSubsLength);
            rewardsForEachSubs = Farm(farm).computeRewards(user, 1);

            vm.expectEmit(address(farm));
            emit RewardsClaimed(depositId, rewardsForEachSubs);
            Farm(farm).claimRewards(depositId);
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
    }

    function test_claimRewards_max_rewards() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 time;
        uint256 rwdRate = 1e19;
        uint256 depositId = 1;
        uint256 rwdBalance = Farm(nonLockupFarm).getRewardBalance(rwdTokens[0]);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        uint256[] memory balances = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; ++i) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(currentActor);
        }
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        // for testing purpose, reward rate is set in a way that we can claim max rewards before farm expiry.
        time = rwdBalance / rwdRate; //Max time to be skipped for claiming max reward
        skip(time + 100); //skip more than the available reward
        rewardsForEachSubs = Farm(nonLockupFarm).computeRewards(currentActor, depositId);

        vm.expectEmit(address(nonLockupFarm));
        emit RewardsClaimed(1, rewardsForEachSubs);
        Farm(nonLockupFarm).claimRewards(depositId);
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
        Farm(nonLockupFarm).setRewardRate(rwdTokens[0], rwdRate);
        uint256[][] memory rewardsForEachSubs = new uint256[][](1);
        skip(time);
        vm.startPrank(user);
        rewardsForEachSubs = Farm(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(nonLockupFarm));
        emit RewardsClaimed(depositId, rewardsForEachSubs);
        Farm(nonLockupFarm).claimRewards(depositId);
        assertEq(rewardsForEachSubs[0][0], 0);
        for (uint8 i; i < rewardTokens.length; ++i) {
            assertEq(IERC20(rewardTokens[i]).balanceOf(currentActor), rewardsForEachSubs[0][i] + balances[i]);
        }
    }
}

abstract contract WithdrawTest is FarmTest {
    function _assertHelperOne(Deposit memory depositInfo) internal {
        assertEq(depositInfo.depositor, address(0));
        assertEq(depositInfo.liquidity, 0);
        assertEq(depositInfo.startTime, 0);
        assertEq(depositInfo.expiryDate, 0);
        assertEq(depositInfo.cooldownPeriod, 0);
    }

    function _assertHelperTwo(
        address farm,
        bool lockup,
        uint256 numDeposits,
        uint256 withdrawnDeposit,
        Deposit[] memory multipleUserDeposits,
        Subscription[] memory multipleUserNonLockUpSubscriptions,
        Subscription[] memory multipleUserLockUpSubscriptions
    ) internal {
        for (uint256 i = 1; i <= numDeposits; i++) {
            user = actors[i];
            if (i == withdrawnDeposit) {
                Deposit memory depositInfo = Farm(farm).getDepositInfo(withdrawnDeposit);
                assertEq(depositInfo.depositor, address(0));
                assertEq(depositInfo.liquidity, 0);
                assertEq(depositInfo.startTime, 0);
                assertEq(depositInfo.expiryDate, 0);
                assertEq(depositInfo.cooldownPeriod, 0);

                vm.expectRevert(abi.encodeWithSelector(Farm.SubscriptionDoesNotExist.selector));
                Farm(farm).getSubscriptionInfo(i, 0);
                if (lockup) {
                    vm.expectRevert(abi.encodeWithSelector(Farm.SubscriptionDoesNotExist.selector));
                    Farm(farm).getSubscriptionInfo(i, 1);
                }
            } else {
                assertEq(
                    keccak256(abi.encode(Farm(farm).getDepositInfo(i))),
                    keccak256(abi.encode(multipleUserDeposits[i - 1]))
                );
                assertEq(
                    keccak256(abi.encode(Farm(farm).getSubscriptionInfo(i, 0))),
                    keccak256(abi.encode(multipleUserNonLockUpSubscriptions[i - 1]))
                );
                if (lockup) {
                    assertEq(
                        keccak256(abi.encode(Farm(farm).getSubscriptionInfo(i, 1))),
                        keccak256(abi.encode(multipleUserLockUpSubscriptions[i - 1]))
                    );
                }
            }
        }
    }

    function test_Withdraw_RevertWhen_PleaseInitiateCooldown()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(Farm.PleaseInitiateCooldown.selector));
        Farm(lockupFarm).withdraw(depositId);
    }

    function test_Withdraw_RevertWhen_DepositIsInCooldown()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        Farm(lockupFarm).initiateCooldown(depositId);
        skip(COOLDOWN_PERIOD_DAYS * 1 days - 100); //100 seconds before the end of CoolDown Period
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositIsInCooldown.selector));
        Farm(lockupFarm).withdraw(depositId);
    }

    function test_withdraw_paused() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            uint256 depositId = 1;
            uint256 time = 3 days;
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.startPrank(owner);
            skip(time);
            uint256[][] memory rewardsForEachSubs;
            if (lockup) {
                rewardsForEachSubs = new uint256[][](2);
            } else {
                rewardsForEachSubs = new uint256[][](1);
            }
            rewardsForEachSubs = Farm(farm).computeRewards(currentActor, 1);
            Farm(farm).farmPauseSwitch(true);
            vm.startPrank(user);
            vm.expectEmit(address(farm));
            emit PoolUnsubscribed(depositId, COMMON_FUND_ID, rewardsForEachSubs[0]);
            if (lockup) {
                vm.expectEmit(address(farm));
                emit PoolUnsubscribed(depositId, LOCKUP_FUND_ID, rewardsForEachSubs[1]);
            }
            vm.expectEmit(address(farm));
            emit DepositWithdrawn(depositId);
            Farm(farm).withdraw(depositId);
            Deposit memory depositInfo = Farm(farm).getDepositInfo(depositId);
            _assertHelperOne(depositInfo);
        }
    }

    function test_withdraw_closed() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            uint256 depositId = 1;
            uint256 time = 3 days;
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.startPrank(owner);
            skip(time);
            Farm(farm).closeFarm();
            vm.startPrank(user);
            vm.expectEmit(address(farm));
            emit DepositWithdrawn(depositId);
            Farm(farm).withdraw(depositId);
            Deposit memory depositInfo = Farm(farm).getDepositInfo(depositId);
            _assertHelperOne(depositInfo);
        }
    }

    function test_withdraw() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 depositId = 1;
            addRewards(farm);
            setRewardRates(farm);
            uint256 liquidity = deposit(farm, lockup, 1e3);

            assertEq(Farm(farm).getDepositInfo(depositId).liquidity, liquidity);

            vm.startPrank(user);
            uint256 time = 2 days;
            uint256 cooldownTime = (COOLDOWN_PERIOD_DAYS * 1 days) + 100;
            uint256[][] memory rewardsForEachSubs = new uint256[][](2);
            if (lockup) {
                Farm(farm).initiateCooldown(depositId);
                skip(cooldownTime); //100 seconds after the end of CoolDown Period
            }
            Farm(farm).getRewardBalance(rwdTokens[0]);
            Farm(farm).getDepositInfo(depositId);
            rewardsForEachSubs = Farm(farm).computeRewards(currentActor, depositId);
            vm.expectEmit(address(farm));
            emit PoolUnsubscribed(depositId, COMMON_FUND_ID, rewardsForEachSubs[0]);
            vm.expectEmit(address(farm));
            emit DepositWithdrawn(depositId);
            Farm(farm).withdraw(depositId);
            skip(time);
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.stopPrank();
            Deposit memory depositInfo = Farm(farm).getDepositInfo(depositId);
            _assertHelperOne(depositInfo);
        }
    }

    function test_withdraw_firstDeposit_multipleDeposits() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 withdrawnDepositId = 1;
            uint256 totalDeposits = 10;
            Deposit[] memory multipleUserDeposits = new Deposit[](10);
            Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
            Subscription[] memory multipleUserLockUpSubscriptions;
            if (lockup) {
                multipleUserLockUpSubscriptions = new Subscription[](10);
            }
            addRewards(farm);
            setRewardRates(farm);
            for (uint256 i = 1; i <= 10; i++) {
                user = actors[i];
                deposit(farm, lockup, i * 1e3);
                multipleUserDeposits[i - 1] = Farm(farm).getDepositInfo(i);
                multipleUserNonLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 0);
                if (lockup) {
                    multipleUserLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 1);
                }
            }

            vm.startPrank(actors[1]);
            uint256 time = 2 days;
            uint256 cooldownTime = (COOLDOWN_PERIOD_DAYS * 1 days) + 100;
            if (lockup) {
                Farm(farm).initiateCooldown(withdrawnDepositId);
                skip(cooldownTime); //100 seconds after the end of CoolDown Period
            }
            Farm(farm).getRewardBalance(rwdTokens[0]);
            Farm(farm).getDepositInfo(withdrawnDepositId);
            Farm(farm).withdraw(withdrawnDepositId);
            skip(time);
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.stopPrank();

            _assertHelperTwo(
                farm,
                lockup,
                totalDeposits,
                withdrawnDepositId,
                multipleUserDeposits,
                multipleUserNonLockUpSubscriptions,
                multipleUserLockUpSubscriptions
            );
        }
    }

    function test_withdraw_inBetweenDeposit_multipleDeposits() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 withdrawnDepositId = 5;
            uint256 totalDeposits = 10;
            Deposit[] memory userDeposits = new Deposit[](10);
            Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
            Subscription[] memory multipleUserLockUpSubscriptions;
            if (lockup) {
                multipleUserLockUpSubscriptions = new Subscription[](10);
            }
            addRewards(farm);
            setRewardRates(farm);
            for (uint256 i = 1; i <= 10; i++) {
                user = actors[i];
                deposit(farm, lockup, i * 1e3);
                userDeposits[i - 1] = Farm(farm).getDepositInfo(i);
                multipleUserNonLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 0);
                if (lockup) {
                    multipleUserLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 1);
                }
            }

            vm.startPrank(actors[5]);
            uint256 time = 2 days;
            uint256 cooldownTime = COOLDOWN_PERIOD_DAYS * 1 days + 100;
            if (lockup) {
                Farm(farm).initiateCooldown(withdrawnDepositId);
                skip(cooldownTime); //100 seconds after the end of CoolDown Period
            }
            Farm(farm).getRewardBalance(rwdTokens[0]);
            Farm(farm).getDepositInfo(withdrawnDepositId);
            Farm(farm).withdraw(withdrawnDepositId);
            skip(time);
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.stopPrank();

            _assertHelperTwo(
                farm,
                lockup,
                totalDeposits,
                withdrawnDepositId,
                userDeposits,
                multipleUserNonLockUpSubscriptions,
                multipleUserLockUpSubscriptions
            );
        }
    }

    function test_withdraw_lastDeposit_multipleDeposits() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 withdrawnDepositId = 10;
            uint256 totalDeposits = 10;
            Deposit[] memory multipleUserDeposits = new Deposit[](10);
            Subscription[] memory multipleUserNonLockUpSubscriptions = new Subscription[](10);
            Subscription[] memory multipleUserLockUpSubscriptions;
            if (lockup) {
                multipleUserLockUpSubscriptions = new Subscription[](10);
            }
            addRewards(farm);
            setRewardRates(farm);
            for (uint256 i = 1; i <= 10; i++) {
                user = actors[i];
                deposit(farm, lockup, i * 1e3);
                multipleUserDeposits[i - 1] = Farm(farm).getDepositInfo(i);
                multipleUserNonLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 0);
                if (lockup) {
                    multipleUserLockUpSubscriptions[i - 1] = Farm(farm).getSubscriptionInfo(i, 1);
                }
            }

            vm.startPrank(actors[10]);
            uint256 time = 2 days;
            uint256 cooldownTime = (COOLDOWN_PERIOD_DAYS * 1 days) + 100;
            if (lockup) {
                Farm(farm).initiateCooldown(withdrawnDepositId);
                skip(cooldownTime); //100 seconds after the end of CoolDown Period
            }
            Farm(farm).getRewardBalance(rwdTokens[0]);
            Farm(farm).getDepositInfo(withdrawnDepositId);
            Farm(farm).withdraw(withdrawnDepositId);
            skip(time);
            Farm(farm).getRewardBalance(rwdTokens[0]);
            vm.stopPrank();

            _assertHelperTwo(
                farm,
                lockup,
                totalDeposits,
                withdrawnDepositId,
                multipleUserDeposits,
                multipleUserNonLockUpSubscriptions,
                multipleUserLockUpSubscriptions
            );
        }
    }
}

abstract contract GetRewardFundInfoTest is FarmTest {
    function test_GetRewardFundInfo_RevertWhen_RewardFundDoesNotExist() public setup useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(Farm.RewardFundDoesNotExist.selector));
        Farm(lockupFarm).getRewardFundInfo(2);
    }

    function test_getRewardFundInfo_LockupFarm() public setup useKnownActor(user) {
        Farm(lockupFarm).getRewardFundInfo(0);
    }
}

abstract contract GetRewardTokensTest is FarmTest {
    function test_GetRewardTokensTest() public setup useKnownActor(user) {
        address[] memory _rwdTokens = Farm(lockupFarm).getRewardTokens();
        uint256 _rwdTokensLen = _rwdTokens.length;
        assertEq(rwdTokens.length, _rwdTokensLen);
        for (uint8 i; i < _rwdTokensLen;) {
            assertEq(_rwdTokens[i], rwdTokens[i]);
            unchecked {
                ++i;
            }
        }
    }
}

abstract contract RecoverERC20Test is FarmTest {
    function test_RecoverERC20_RevertWhen_CannotWithdrawRewardToken() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(Farm.CannotWithdrawRewardToken.selector));
        Farm(lockupFarm).recoverERC20(rwdTokens[0]);
    }

    function test_RecoverERC20_RevertWhen_CannotWithdrawZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(Farm.CannotWithdrawZeroAmount.selector));
        Farm(lockupFarm).recoverERC20(USDT);
    }

    function testFuzz_recoverE20(bool lockup, uint256 amt) public useKnownActor(owner) {
        address farm = lockup ? lockupFarm : nonLockupFarm;
        amt = bound(amt, 1000 * 10 ** ERC20(USDT).decimals(), 10000 * 10 ** ERC20(USDT).decimals());
        deal(USDT, address(farm), 10e10);
        vm.expectEmit(address(farm));
        emit RecoveredERC20(USDT, 10e10);
        Farm(farm).recoverERC20(USDT);
    }
}

abstract contract InitiateCooldownTest is FarmTest {
    // this check is to make sure someone else other than the depositor cannot initiate cooldown
    function test_initiateCooldown_RevertWhen_DepositDoesNotExist()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(actors[9])
    {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        Farm(lockupFarm).initiateCooldown(depositId);
    }

    function test_initiateCooldown_LockupFarm() public setup depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        Deposit memory userDeposit = Farm(lockupFarm).getDepositInfo(depositId);
        skip(7 days);
        uint256[][] memory rewardsForEachSubs = new uint256[][](2);
        rewardsForEachSubs = Farm(lockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(address(lockupFarm));
        emit RewardsClaimed(depositId, rewardsForEachSubs);
        vm.expectEmit(address(lockupFarm));
        emit PoolUnsubscribed(depositId, LOCKUP_FUND_ID, rewardsForEachSubs[1]);
        vm.expectEmit(address(lockupFarm));
        emit CooldownInitiated(depositId, userDeposit.startTime + ((COOLDOWN_PERIOD_DAYS + 7) * 1 days));
        Farm(lockupFarm).initiateCooldown(depositId);
    }

    function test_initiateCooldown_nonLockupFarm()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(Farm.CannotInitiateCooldown.selector));
        Farm(nonLockupFarm).initiateCooldown(1);
    }
}

abstract contract AddRewardsTest is FarmTest {
    function test_AddRewards_RevertWhen_InvalidRewardToken() public useKnownActor(owner) {
        uint256 rwdAmt = 1 * 10 ** ERC20(invalidRewardToken).decimals();
        deal(address(invalidRewardToken), currentActor, rwdAmt);
        ERC20(invalidRewardToken).approve(nonLockupFarm, rwdAmt);
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidRewardToken.selector));
        Farm(nonLockupFarm).addRewards(invalidRewardToken, rwdAmt);
    }

    function test_AddRewards_RevertWhen_ZeroAmount() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(Farm.ZeroAmount.selector));
        Farm(lockupFarm).addRewards(USDCe, 0);
    }

    function testFuzz_addRewards(bool lockup, uint256 rwdAmt) public useKnownActor(owner) {
        address farm = lockup ? lockupFarm : nonLockupFarm;
        address[] memory rewardTokens = getRewardTokens(farm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            rwdAmt = bound(rwdAmt, 1000 * 10 ** decimals, 10000 * 10 ** decimals);
            deal(address(rewardTokens[i]), currentActor, rwdAmt);
            ERC20(rewardTokens[i]).approve(address(farm), rwdAmt);
            vm.expectEmit(address(farm));
            emit RewardAdded(rewardTokens[i], rwdAmt);
            Farm(farm).addRewards(rewardTokens[i], rwdAmt);
            assertEq(Farm(farm).getRewardBalance(rewardTokens[i]), rwdAmt);
        }
    }
}

abstract contract SetRewardRateTest is FarmTest {
    function test_SetRewardRate_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](1);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        rwdRate[0] = ERC20(rewardTokens[0]).decimals();
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).setRewardRate(rewardTokens[0], rwdRate);
    }

    function test_SetRewardRate_RevertWhen_InvalidRewardRatesLength() public useKnownActor(owner) {
        uint256[] memory rwdRate = new uint256[](1);
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        for (uint8 i; i < rewardTokens.length; ++i) {
            uint8 decimals = ERC20(rewardTokens[i]).decimals();
            rwdRate[0] = 2 * 10 ** decimals;
            vm.startPrank(currentActor);
            vm.expectRevert(abi.encodeWithSelector(Farm.InvalidRewardRatesLength.selector));
            Farm(lockupFarm).setRewardRate(rewardTokens[i], rwdRate);
        }
    }

    function testFuzz_setRewardRate(bool lockup, uint256 rwdRateNonLockup, uint256 rwdRateLockup) public {
        address farm = lockup ? lockupFarm : nonLockupFarm;
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

            vm.expectEmit(address(farm));
            emit RewardRateUpdated(rewardTokens[i], rwdRate);
            Farm(farm).setRewardRate(rewardTokens[i], rwdRate);
            assertEq(Farm(farm).getRewardRates(rewardTokens[i]), rwdRate);
        }
    }
}

abstract contract GetRewardBalanceTest is FarmTest {
    function test_GetRewardBalance_RevertWhen_InvalidRewardToken()
        public
        setup
        depositSetup(lockupFarm, true)
        useKnownActor(owner)
    {
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidRewardToken.selector));
        Farm(nonLockupFarm).getRewardBalance(invalidRewardToken);
    }

    function test_rewardBalance() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            for (uint8 i = 0; i < rwdTokens.length; ++i) {
                uint256 rwdBalance = Farm(farm).getRewardBalance(rwdTokens[i]);
                assert(rwdBalance != 0);
            }
        }
    }
}

abstract contract GetDepositTest is FarmTest {
    function test_GetDeposit_RevertWhen_DepositDoesNotExist() public setup {
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        Farm(nonLockupFarm).getDepositInfo(0);

        uint256 totalDeposits = Farm(nonLockupFarm).totalDeposits();

        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        Farm(nonLockupFarm).getDepositInfo(totalDeposits + 1);
    }
}

abstract contract GetNumSubscriptionsTest is FarmTest {
    function test_getDeposit() public setup depositSetup(nonLockupFarm, false) useKnownActor(user) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 numSubscriptions = Farm(farm).getNumSubscriptions(0);
            assertEq(numSubscriptions, 0);
        }
    }
}

abstract contract SubscriptionInfoTest is FarmTest {
    function test_SubscriptionInfo_RevertWhen_SubscriptionDoesNotExist()
        public
        setup
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(Farm.SubscriptionDoesNotExist.selector));
        Farm(nonLockupFarm).getSubscriptionInfo(1, 2);
    }

    function test_subInfo() public setup {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            Subscription memory numSubscriptions = Farm(farm).getSubscriptionInfo(1, 0);
            assertEq(numSubscriptions.fundId, 0);
        }
    }
}

abstract contract UpdateRewardTokenDataTest is FarmTest {
    function test_UpdateRewardTokenData_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;

        vm.startPrank(owner);
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_UpdateRewardTokenData_RevertWhen_NotTheTokenManager() public useKnownActor(user) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = newTokenManager;
        vm.expectRevert(abi.encodeWithSelector(Farm.NotTheTokenManager.selector));
        Farm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_UpdateRewardTokenData_RevertWhen_InvalidAddress() public useKnownActor(owner) {
        address[] memory rewardTokens = getRewardTokens(nonLockupFarm);
        address _newTknManager = address(0);
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidAddress.selector));
        Farm(nonLockupFarm).updateRewardData(rewardTokens[0], _newTknManager);
    }

    function test_updateTknManager() public useKnownActor(owner) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            address[] memory rewardTokens = getRewardTokens(farm);
            address _newTknManager = newTokenManager;
            for (uint8 i; i < rewardTokens.length; ++i) {
                address rwdToken = rewardTokens[i];

                vm.expectEmit(address(farm));
                emit RewardDataUpdated(rwdToken, _newTknManager);
                Farm(farm).updateRewardData(rwdToken, _newTknManager);
            }
        }
    }
}

abstract contract RecoverRewardFundsTest is FarmTest {
    function test_recoverRewardFund_AfterAddRewards() public {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            depositSetupFn(farm, lockup);
            vm.startPrank(owner);
            address[] memory rewardTokens = getRewardTokens(farm);

            for (uint8 i; i < rewardTokens.length; ++i) {
                address rwdToken = rewardTokens[i];
                uint256 rwdBalance = ERC20(rwdToken).balanceOf(farm);

                vm.expectEmit(address(farm));
                emit FundsRecovered(owner, rwdToken, rwdBalance);
                Farm(farm).recoverRewardFunds(rwdToken, rwdBalance);
            }
        }
    }

    function test_recoverRewardFund_WithDirectlySentFunds() public setup useKnownActor(owner) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            address[] memory rewardTokens = getRewardTokens(farm);

            for (uint8 i; i < rewardTokens.length; ++i) {
                address rwdToken = rewardTokens[i];
                deal(rwdToken, farm, 1e3);
                uint256 rwdBalance = ERC20(rwdToken).balanceOf(farm);

                vm.expectEmit(address(farm));
                emit FundsRecovered(currentActor, rwdToken, rwdBalance);
                Farm(farm).recoverRewardFunds(rwdToken, rwdBalance);
            }
        }
    }

    function test_recoverRewardFund_partially() public useKnownActor(owner) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            address[] memory rewardTokens = getRewardTokens(farm);

            for (uint8 i; i < rewardTokens.length; ++i) {
                address rwdToken = rewardTokens[i];
                deal(rwdToken, farm, 6e6);
                uint256 rwdToRecover = 5e6;
                uint256 rwdBalanceBefore = ERC20(rwdToken).balanceOf(farm);

                vm.expectEmit(address(farm));
                emit FundsRecovered(currentActor, rwdToken, rwdToRecover);
                Farm(farm).recoverRewardFunds(rwdToken, rwdToRecover);

                uint256 rwdBalanceAfter = ERC20(rwdToken).balanceOf(farm);
                assertEq(rwdBalanceAfter, rwdBalanceBefore - rwdToRecover);
            }
        }
    }
}

abstract contract FarmPauseSwitchTest is FarmTest {
    function test_FarmPauseSwitch_RevertWhen_FarmAlreadyInRequiredState() public useKnownActor(owner) {
        bool isFarmActive = Farm(nonLockupFarm).isFarmActive();
        isFarmActive = !isFarmActive;
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmAlreadyInRequiredState.selector));
        Farm(nonLockupFarm).farmPauseSwitch(isFarmActive);
    }

    function test_FarmPauseSwitch_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        bool isFarmActive = Farm(nonLockupFarm).isFarmActive();
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).farmPauseSwitch(isFarmActive);
    }

    function test_farmPause() public useKnownActor(owner) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            bool isFarmActive = Farm(farm).isFarmActive();
            vm.expectEmit(address(farm));
            emit FarmPaused(isFarmActive);
            Farm(farm).farmPauseSwitch(isFarmActive);
        }
    }
}

abstract contract UpdateFarmStartTimeTest is FarmTest {
    function test_UpdateFarmStartTime_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_UpdateFarmStartTime_RevertWhen_FarmAlreadyStarted() public useKnownActor(owner) {
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmAlreadyStarted.selector));
        Farm(nonLockupFarm).updateFarmStartTime(block.timestamp);
    }

    function test_UpdateFarmStartTime_RevertWhen_InvalidTime() public {
        address farm = createFarm(block.timestamp + 2000, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidTime.selector));
        Farm(farm).updateFarmStartTime(block.timestamp - 1);
    }

    function testFuzz_updateFarmStartTime(bool lockup, uint256 farmStartTime, uint256 newStartTime) public {
        farmStartTime = bound(farmStartTime, block.timestamp + 2, type(uint64).max);
        newStartTime = bound(newStartTime, farmStartTime - 1, type(uint64).max);
        address farm = createFarm(farmStartTime, lockup);

        vm.startPrank(owner);
        vm.expectEmit(address(farm));
        emit FarmStartTimeUpdated(newStartTime);
        Farm(farm).updateFarmStartTime(newStartTime);
        vm.stopPrank();

        uint256 lastFundUpdateTime = Farm(farm).lastFundUpdateTime();

        assertEq(lastFundUpdateTime, newStartTime);
    }
}

abstract contract UpdateCoolDownPeriodTest is FarmTest {
    function test_UpdateCoolDownPeriod_noLockupFarm() public useKnownActor(owner) {
        uint256 cooldownPeriodInDays = 20;
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmDoesNotSupportLockup.selector));
        Farm(nonLockupFarm).updateCooldownPeriod(cooldownPeriodInDays);
    }

    function test_UpdateCoolDownPeriod_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        uint256 cooldownPeriodInDays = 20;
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).updateCooldownPeriod(cooldownPeriodInDays);
    }

    function test_UpdateCoolDownPeriod_RevertWhen_InvalidCooldownPeriod() public useKnownActor(owner) {
        uint256 cooldownPeriodInDays = 31;
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidCooldownPeriod.selector));
        Farm(lockupFarm).updateCooldownPeriod(cooldownPeriodInDays);
    }

    function test_UpdateCoolDownPeriod_RevertWhen_InvalidCooldownPeriod0() public useKnownActor(owner) {
        uint256 cooldownPeriodInDays = 0;
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidCooldownPeriod.selector));
        Farm(lockupFarm).updateCooldownPeriod(cooldownPeriodInDays);
    }

    function testFuzz_updateCoolDown_lockupFarm(uint256 cooldownPeriodInDays) public useKnownActor(owner) {
        vm.assume(cooldownPeriodInDays >= MIN_COOLDOWN_PERIOD_DAYS && cooldownPeriodInDays <= MAX_COOLDOWN_PERIOD_DAYS);

        vm.expectEmit(address(lockupFarm));
        emit CooldownPeriodUpdated(cooldownPeriodInDays);
        Farm(lockupFarm).updateCooldownPeriod(cooldownPeriodInDays);
    }
}

abstract contract CloseFarmTest is FarmTest {
    function test_CloseFarm_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        Farm(nonLockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        Farm(nonLockupFarm).closeFarm();
    }

    function test_closeFarm() public useKnownActor(owner) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            uint256 rewardRateLength = lockup ? 2 : 1;
            address[] memory rewardTokens = getRewardTokens(farm);
            uint256[] memory rwdRate = new uint256[](rewardRateLength);
            vm.expectEmit(address(farm));
            emit FarmClosed();
            Farm(farm).closeFarm();
            assertEq(Farm(farm).isFarmOpen(), false);
            assertEq(Farm(farm).isFarmActive(), false);
            for (uint256 i = 0; i < rwdTokens.length; i++) {
                assertEq(Farm(farm).getRewardRates(rewardTokens[i]), rwdRate);
            }

            // this function also recovers reward funds. Need to test that here.
        }
    }
}

abstract contract _SetupFarmTest is FarmTest {
    function test_SetupFarm_RevertWhen_InvalidFarmStartTime() public {
        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidFarmStartTime.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp - 200, false));
        assertTrue(success);
    }

    function test_SetupFarm_RevertWhen_InvalidRewardData() public {
        do {
            rwdTokens.push(USDCe);
        } while (rwdTokens.length <= MAX_NUM_REWARDS); // <= So that rwdTokens.length becomes MAX_NUM_REWARDS + 1

        vm.expectRevert(abi.encodeWithSelector(Farm.InvalidRewardData.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }

    function test_SetupFarm_MAX_NUM_REWARDS() public {
        rwdTokens = new address[](4);
        rwdTokens[0] = USDCe;
        rwdTokens[1] = DAI;
        rwdTokens[2] = SPA;
        rwdTokens[3] = USDT;
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }

    function test_SetupFarm_RevertWhen_RewardAlreadyAdded() public {
        rwdTokens.push(rwdTokens[0]);

        vm.expectRevert(abi.encodeWithSelector(Farm.RewardTokenAlreadyAdded.selector));
        (bool success,) =
            address(this).call(abi.encodeWithSignature("createFarm(uint256,bool)", block.timestamp, false));
        assertTrue(success);
    }
}

abstract contract MulticallTest is FarmTest {
    function testFuzz_Multicall(uint256 cooldownPeriodInDays) public useKnownActor(owner) {
        cooldownPeriodInDays = bound(cooldownPeriodInDays, MIN_COOLDOWN_PERIOD_DAYS, MAX_COOLDOWN_PERIOD_DAYS);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(Farm.updateCooldownPeriod.selector, cooldownPeriodInDays);
        data[1] = abi.encodeWithSelector(Farm.closeFarm.selector);

        Farm(lockupFarm).multicall(data);

        assertEq(Farm(lockupFarm).cooldownPeriod(), cooldownPeriodInDays * 1 days);
        assertEq(Farm(lockupFarm).isFarmOpen(), false);
    }

    function testFuzz_Multicall_RevertWhen_AnyIndividualTestFail(uint256 cooldownPeriodInDays)
        public
        useKnownActor(owner)
    {
        // when any multiple calls fail
        {
            bytes[] memory data = new bytes[](1);
            // This should revert as farm already started.
            data[0] = abi.encodeWithSelector(Farm.updateFarmStartTime.selector, block.timestamp + 200);

            vm.expectRevert(abi.encodeWithSelector(Farm.FarmAlreadyStarted.selector));
            Farm(lockupFarm).multicall(data);
        }

        // when one of multiple calls fail
        {
            cooldownPeriodInDays = bound(cooldownPeriodInDays, MIN_COOLDOWN_PERIOD_DAYS, MAX_COOLDOWN_PERIOD_DAYS);

            // When any single call fails the whole transaction should revert.
            bytes[] memory data = new bytes[](3);
            data[0] = abi.encodeWithSelector(Farm.updateCooldownPeriod.selector, cooldownPeriodInDays);
            // This should revert as farm already started.
            data[1] = abi.encodeWithSelector(Farm.updateFarmStartTime.selector, block.timestamp + 200);
            data[2] = abi.encodeWithSelector(Farm.closeFarm.selector);

            vm.expectRevert(abi.encodeWithSelector(Farm.FarmAlreadyStarted.selector));
            Farm(lockupFarm).multicall(data);
        }

        // checking sender
        {
            changePrank(user);
            cooldownPeriodInDays = bound(cooldownPeriodInDays, MIN_COOLDOWN_PERIOD_DAYS, MAX_COOLDOWN_PERIOD_DAYS);

            // When any single call fails the whole transaction should revert.
            bytes[] memory data = new bytes[](3);
            data[0] = abi.encodeWithSelector(Farm.updateCooldownPeriod.selector, cooldownPeriodInDays);

            vm.expectRevert("Ownable: caller is not the owner");
            Farm(lockupFarm).multicall(data);
        }
    }

    function test_Multicall_RevertWhen_CallInternalFunction() public useKnownActor(owner) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("_updateFarmRewardData()");

        vm.expectRevert("Address: low-level delegate call failed");
        Farm(lockupFarm).multicall(data);
    }
}

abstract contract FarmInheritTest is
    DepositTest,
    ClaimRewardsTest,
    WithdrawTest,
    GetRewardFundInfoTest,
    RecoverERC20Test,
    InitiateCooldownTest,
    AddRewardsTest,
    SetRewardRateTest,
    GetRewardBalanceTest,
    GetDepositTest,
    GetNumSubscriptionsTest,
    GetRewardTokensTest,
    SubscriptionInfoTest,
    UpdateRewardTokenDataTest,
    RecoverRewardFundsTest,
    FarmPauseSwitchTest,
    UpdateFarmStartTimeTest,
    UpdateCoolDownPeriodTest,
    CloseFarmTest,
    _SetupFarmTest,
    MulticallTest
{}
