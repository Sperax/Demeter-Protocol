// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import {BaseFarm} from "../contracts/BaseFarm.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../test/utils/DeploymentSetup.sol";
import {FarmFactory} from "../../contracts/farmFactory.sol";
import {BaseFarmDeployer} from "../../contracts/BaseFarmDeployer.sol";
import {BaseFarm, RewardTokenData} from "../../contracts/BaseFarm.sol";
import {Demeter_BalancerFarm} from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm.sol";
import {Demeter_BalancerFarm_Deployer} from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";
import {console} from "forge-std/console.sol";

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

interface IBalancerVault {
    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }

    function getPool(bytes32 poolId)
        external
        view
        returns (address, PoolSpecialization);

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
}

contract BaseFarmTest is PreMigrationSetup {
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
    // struct Deposit {
    //   uint256 liquidity;
    //   uint256 tokenId;
    //   uint256 startTime;
    //   uint256 expiryDate;
    //   uint256 cooldownPeriod;
    //   uint256[] totalRewardsClaimed;
    // }
    RewardFund[] public rewardFunds;
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
        setRewardRates(nonLockupFarm);
        setRewardRates(lockupFarm);
        deposit(nonLockupFarm, false);
        deposit(lockupFarm, true);
    }
}

contract deposit is BaseFarmTest {
    function test_noLockupFarm_revertsWhen_0Liquidity() public useActor(4) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);

        deal(poolAddress, currentActor, 0);
        ERC20(poolAddress).approve(address(nonLockupFarm), 0);
        vm.expectRevert("No liquidity in position");

        nonLockupFarm.deposit(0, false);
    }

    function test_noLockupFarm_revertsWhen_lockupDeposit(uint256 amt)
        public
        useActor(4)
    {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);

        vm.assume(
            amt > 100 * 10**ERC20(poolAddress).decimals() &&
                amt <= 1000 * 10**ERC20(poolAddress).decimals()
        );

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);
        vm.expectRevert("Lockup functionality is disabled");

        nonLockupFarm.deposit(amt, true);
    }

    function test_noLockupFarm_deposit(uint256 amt) public useActor(4) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);

        vm.assume(
            amt > 100 * 10**ERC20(poolAddress).decimals() &&
                amt <= 1000 * 10**ERC20(poolAddress).decimals()
        );

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(nonLockupFarm), amt);
        vm.expectEmit(true, true, false, true);
        emit Deposited(
            currentActor,
            false,
            nonLockupFarm.getNumDeposits(currentActor) + 1,
            amt
        );
        nonLockupFarm.deposit(amt, false);
    }

    function test_lockupFarm(uint256 amt) public useActor(4) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);

        vm.assume(
            amt > 100 * 10**ERC20(poolAddress).decimals() &&
                amt <= 1000 * 10**ERC20(poolAddress).decimals()
        );

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        vm.expectEmit(true, true, false, true);
        emit Deposited(
            currentActor,
            true,
            nonLockupFarm.getNumDeposits(currentActor) + 1,
            amt
        );
        lockupFarm.deposit(amt, true);
    }
    //   function test_lockupFarm(uint256 amt) public useActor(5) {
    //     deposit(lockupFarm,true);
    // }
}

contract increaseDeposit is BaseFarmTest {
    function test_lockupFarm(uint256 amt) public useActor(5) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
        setupFarmRewards();

        vm.assume(
            amt > 100 * 10**ERC20(poolAddress).decimals() &&
                amt <= 1000 * 10**ERC20(poolAddress).decimals()
        );

        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(lockupFarm), amt);
        lockupFarm.increaseDeposit(0, amt);
    }
}

contract fullWithdraw is BaseFarmTest {
    function test_lockupFarm_RevertsWhen_Cooldown_IsntInitiated()
        public
        useActor(5)
    {
        setupFarmRewards();
        vm.expectRevert("Please initiate cooldown");
        lockupFarm.withdraw(0);
    }

    function test_lockupFarm_RevertsWhen_Cooldown_notFinished()
        public
        useActor(5)
    {
        setupFarmRewards();
        lockupFarm.initiateCooldown(0);
        skip((COOLDOWN_PERIOD * 86400) - 100); //100 seconds before the end of CoolDown Period
        vm.expectRevert("Deposit is in cooldown");
        lockupFarm.withdraw(0);
    }

    function test_lockupFarm() public useActor(5) {
        setupFarmRewards();
        lockupFarm.initiateCooldown(0);
        skip((COOLDOWN_PERIOD * 86400) + 100); //100 seconds after the end of CoolDown Period

        lockupFarm.withdraw(0);
    }

    function test_lockupFarm_paused() public useActor(5) {
        setupFarmRewards();

        //lockupFarm.deposit storage userDeposit = lockupFarm.getDeposit(currentActor,0); //out of bounds
        skip(86400 * 2);
        lockupFarm.initiateCooldown(0);
        vm.startPrank(actors[1]);
        skip(86400 * 2);
        lockupFarm.farmPauseSwitch(true);
        vm.startPrank(actors[5]);
        skip(86400 * 2);
        uint256[] memory rewards = lockupFarm.computeRewards(currentActor, 0);

        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(
            currentActor,
            0,
            1,
            1000000000000000000000,
            1000000000000000000000,
            rewards
        );
        lockupFarm.withdraw(0);
    }

    function test_nonLockupFarm() public useActor(5) {
        setupFarmRewards();
        lockupFarm.initiateCooldown(0);
        skip((COOLDOWN_PERIOD * 86400) + 100); //100 seconds after the end of CoolDown Period

        nonLockupFarm.withdraw(0);
    }
}

contract withdrawPartially is BaseFarmTest {
    function test_zeroAmount() public useActor(5) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
        setupFarmRewards();

        // lockupFarm.initiateCooldown(0);
        vm.expectRevert("Invalid amount");
        nonLockupFarm.withdrawPartially(0, 0);
    }

    function test_LockupFarm() public useActor(5) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
        setupFarmRewards();

        skip(86400 * 7);
        vm.expectRevert("Partial withdraw not permitted");
        lockupFarm.withdrawPartially(0, 10000);
    }

    function test_nonLockupFarm() public useActor(5) {
        address poolAddress;
        (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
        setupFarmRewards();

        // lockupFarm.initiateCooldown(0);
        skip(86400 * 7);
        nonLockupFarm.computeRewards(currentActor, 0);
        nonLockupFarm.withdrawPartially(0, 10000);
    }
}

contract getRewardFundInfo is BaseFarmTest {
    function test_LockupFarm_rewardDoesntExist() public useActor(5) {
        setupFarmRewards();

        vm.expectRevert("Reward fund does not exist");
        lockupFarm.getRewardFundInfo(2);
    }

    function test_LockupFarm() public useActor(5) {
        setupFarmRewards();

        lockupFarm.getRewardFundInfo(0);
    }
}

contract recoverERC20 is BaseFarmTest {
    function test_LockupFarm_revertsWhenRewardToken() public useActor(1) {
        vm.expectRevert("Can't withdraw rewardToken or farmToken");
        lockupFarm.recoverERC20(USDCe);
    }

    function test_LockupFarm_revertsWhenZeroAmount() public useActor(1) {
        vm.expectRevert("Can't withdraw 0 amount");
        lockupFarm.recoverERC20(USDT);
    }

    function test_LockupFarm_(uint256 amt) public useActor(1) {
        bound(
            amt,
            1000 * 10**ERC20(USDT).decimals(),
            10000 * 10**ERC20(USDT).decimals()
        );
        deal(USDT, address(lockupFarm), 10e10);
        vm.expectEmit(true, true, false, false);
        emit RecoveredERC20(USDT, 10e10);
        lockupFarm.recoverERC20(USDT);
    }
}

contract initiateCooldown is BaseFarmTest {
    function test_LockupFarm() public useActor(5) {
        setupFarmRewards();

        skip(86400 * 7);
        vm.expectEmit(true, true, false, false);
        emit CooldownInitiated(currentActor, 1, COOLDOWN_PERIOD * 1 days);
        lockupFarm.initiateCooldown(0);
    }

    function test_nonLockupFarm() public useActor(5) {
        setupFarmRewards();

        // lockupFarm.initiateCooldown(0);
        skip(86400 * 7);
        vm.expectRevert("Can not initiate cooldown");
        nonLockupFarm.initiateCooldown(0);
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
    function test_noLockupFarm_revertsWhen_farmIsClosed(
        uint256 rwdRateNonLockup
    ) public useActor(1) {
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
            lockupFarm.closeFarm();
            vm.expectRevert("Farm closed");

            lockupFarm.setRewardRate(rewardTokens[i], rwdRate);
        }
    }

    function test_noLockupFarm_revertsWhen_invalidLength(
        uint256 rwdRateNonLockup
    ) public useActor(1) {
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
            console.log(nonLockupFarm.getRewardRates(rewardTokens[i])[0]);
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
            console.log(lockupFarm.getRewardRates(rewardTokens[i])[0]);
        }
    }
}

contract updateTokenManager is BaseFarmTest {
    function test_nonLockupFarm_revertsWhen_closedFarm() public useActor(0) {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        address _newTknManager = actors[3];
        for (uint8 i; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }
            nonLockupFarm.closeFarm();
            vm.expectRevert("Farm closed");
            nonLockupFarm.updateTokenManager(rewardTokens[i], _newTknManager);
        }
    }

    function test_nonLockupFarm_revertsWhen_invalidTokenManager()
        public
        useActor(0)
    {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        address _newTknManager = actors[3];
        for (uint8 i; i < rewardTokens.length; ++i) {
            nonLockupFarm.closeFarm();
            vm.expectRevert("Not the token manager");
            nonLockupFarm.updateTokenManager(rewardTokens[i], _newTknManager);
        }
    }

    function test_nonLockupFarm() public useActor(0) {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        address _newTknManager = actors[3];
        for (uint8 i; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, false, false, false);
            emit TokenManagerUpdated(
                rewardTokens[i],
                currentActor,
                _newTknManager
            );
            nonLockupFarm.updateTokenManager(rewardTokens[i], _newTknManager);
        }
    }

    function test_LockupFarm() public useActor(1) {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        address _newTknManager = actors[4];
        for (uint8 i; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }

            vm.expectEmit(true, false, false, false);
            emit TokenManagerUpdated(
                rewardTokens[i],
                currentActor,
                _newTknManager
            );
            lockupFarm.updateTokenManager(rewardTokens[i], _newTknManager);
        }
    }
}

contract recoverRewardFunds is BaseFarmTest {
    function test_nonLockupFarm() public useActor(0) {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        setupFarmRewards();

        for (uint8 i; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }
            emit FundsRecovered(
                currentActor,
                rewardTokens[i],
                ERC20(rewardTokens[i]).balanceOf(address(nonLockupFarm))
            );
            nonLockupFarm.recoverRewardFunds(
                rewardTokens[i],
                ERC20(rewardTokens[i]).balanceOf(address(nonLockupFarm))
            );
        }
    }

    function test_lockupFarm() public useActor(1) {
        address[] memory rewardTokens = lockupFarm.getRewardTokens();
        setupFarmRewards();

        for (uint8 i; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == SPA) {
                vm.startPrank(SPA_MANAGER);
            } else {
                vm.startPrank(currentActor);
            }
            emit FundsRecovered(
                currentActor,
                rewardTokens[i],
                ERC20(rewardTokens[i]).balanceOf(address(lockupFarm))
            );
            lockupFarm.recoverRewardFunds(
                rewardTokens[i],
                ERC20(rewardTokens[i]).balanceOf(address(lockupFarm))
            );
        }
    }

    // function test_lockupFarm_partially() public useActor(1) {
    //   address[] memory rewardTokens = lockupFarm.getRewardTokens();
    //   setupFarmRewards();

    //   for (uint8 i; i < rewardTokens.length; ++i) {
    //     if (rewardTokens[i] == SPA) {
    //       vm.startPrank(SPA_MANAGER);
    //     } else {
    //       vm.startPrank(currentActor);
    //     }
    //     emit FundsRecovered(
    //       currentActor,
    //       rewardTokens[i],
    //       ERC20(rewardTokens[i]).balanceOf(address(lockupFarm)) - 1e7
    //     );
    //     lockupFarm.recoverRewardFunds(
    //       rewardTokens[i],
    //       ERC20(rewardTokens[i]).balanceOf(address(lockupFarm)) - 1e7
    //     );
    //     emit FundsRecovered(currentActor, rewardTokens[i], 5e6);
    //     lockupFarm.recoverRewardFunds(rewardTokens[i], 5e6);
    //   }
    // }
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
            farmStartTime > block.timestamp + 2 &&
                newStartTime == farmStartTime - 1
        );
        createNonLockupFarm(farmStartTime);
        vm.startPrank(actors[0]);
        vm.expectEmit(true, true, false, true);
        emit FarmStartTimeUpdated(newStartTime);
        nonLockupFarm.updateFarmStartTime(newStartTime);
    }

    function test_lockupFarm(uint256 farmStartTime, uint256 newStartTime)
        public
    {
        vm.assume(
            farmStartTime > block.timestamp + 2 &&
                newStartTime == farmStartTime - 1
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
