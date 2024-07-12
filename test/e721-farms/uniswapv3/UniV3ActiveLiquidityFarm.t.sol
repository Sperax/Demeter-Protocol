// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../../contracts/e721-farms/uniswapV3/UniV3ActiveLiquidityFarm.sol";
import "../../../contracts/e721-farms/uniswapV3/UniV3ActiveLiquidityDeployer.sol";
import "../../../contracts/e721-farms/uniswapV3/UniV3Farm.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import "../../Farm.t.sol";
import "../../features/ExpirableFarm.t.sol";
import "./UniV3Farm.t.sol";
import {VmSafe} from "forge-std/Vm.sol";

abstract contract UniV3ActiveLiquidityFarmTest is UniV3FarmTest {
    UniV3ActiveLiquidityDeployer public uniV3ActiveLiqFarmDeployer;

    function setUp() public virtual override {
        FarmTest.setUp();
        vm.startPrank(PROXY_OWNER);
        address impl = address(new UniV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        IFarmRegistry registry = IFarmRegistry(FARM_REGISTRY);
        uniV3ActiveLiqFarmDeployer = new UniV3ActiveLiquidityDeployer(
            FARM_REGISTRY, FARM_ID, UNIV3_FACTORY, NFPM, UNISWAP_UTILS, NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        registry.registerFarmDeployer(address(uniV3ActiveLiqFarmDeployer));

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

        invalidRewardToken = USDT;

        vm.stopPrank();

        // Create and setup Farms
        lockupFarm = createFarm(block.timestamp, true);
        nonLockupFarm = createFarm(block.timestamp, false);
    }

    function createFarm(uint256 _startTime, bool _lockup) public virtual override returns (address) {
        return UniV3FarmTest.createFarm(_startTime, _lockup);
    }

    function deposit(address _farm, bool _locked, uint256 _baseAmt) public virtual override returns (uint256) {
        return UniV3FarmTest.deposit(_farm, _locked, _baseAmt);
    }

    function _mockUniswapV3PoolTick(address farm, bool _shouldMock) internal {
        address uniswapPool = UniV3ActiveLiquidityFarm(farm).uniswapPool();
        (
            uint160 sqrtPriceX96,
            ,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = IUniswapV3PoolState(uniswapPool).slot0();

        _shouldMock
            ? vm.mockCall(
                uniswapPool,
                abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
                abi.encode(
                    sqrtPriceX96,
                    TICK_UPPER + 1,
                    observationIndex,
                    observationCardinality,
                    observationCardinalityNext,
                    feeProtocol,
                    unlocked
                )
            )
            : vm.clearMockedCalls();
    }

    function _mockUniswapV3PoolSnapshot(address farm, bool _shouldMock, uint256 _skipTime)
        internal
        returns (uint256 mockedSecondsInside)
    {
        address uniswapPool = UniV3ActiveLiquidityFarm(farm).uniswapPool();
        (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside) =
            IUniswapV3PoolDerivedState(uniswapPool).snapshotCumulativesInside(TICK_LOWER, TICK_UPPER);

        mockedSecondsInside = secondsInside - _skipTime;
        _shouldMock
            ? vm.mockCall(
                uniswapPool,
                abi.encodeWithSelector(
                    IUniswapV3PoolDerivedState.snapshotCumulativesInside.selector, TICK_LOWER, TICK_UPPER
                ),
                abi.encode(tickCumulativeInside, secondsPerLiquidityInsideX128, mockedSecondsInside)
            )
            : vm.clearMockedCalls();
    }
}

// TODO add compute rewards tests
// TODO fix the following tests
abstract contract ActiveLiquidityTest is UniV3ActiveLiquidityFarmTest {
    function test_IsFarmActive_When_InactiveLiquidity() public {
        // Assuming farm is always in active liquidity as tick range is huge.
        assertTrue(UniV3ActiveLiquidityFarm(lockupFarm).isFarmActive());
        _mockUniswapV3PoolTick(lockupFarm, true);
        assertFalse(UniV3ActiveLiquidityFarm(lockupFarm).isFarmActive());

        // Functions dependent on isFarmActive should revert.
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsInactive.selector));
        UniV3ActiveLiquidityFarm(lockupFarm).initiateCooldown(1); // bogus depositId
    }

    function test_Withdraw_When_InactiveLiquidity() public depositSetup(lockupFarm, true) {
        vm.startPrank(user);
        uint256 depositId = 1;
        _mockUniswapV3PoolTick(lockupFarm, true);
        vm.expectEmit(NFPM);
        emit Transfer(lockupFarm, currentActor, UniV3ActiveLiquidityFarm(lockupFarm).depositToTokenId(depositId));

        UniV3ActiveLiquidityFarm(lockupFarm).withdraw(depositId);
    }

    function test_ComputeRewards_For_ActiveLiquidity() public depositSetup(lockupFarm, true) {
        uint256 increaseTime = 10 days;
        uint24[3] memory skipActiveTime = [0, 5 days, 10 days];
        skip(increaseTime);
        uint256[][] memory rewards = UniV3ActiveLiquidityFarm(lockupFarm).computeRewards(currentActor, depositId);

        for (uint256 i; i < skipActiveTime.length; i++) {
            vm.clearMockedCalls();
            uint256 activeTime = increaseTime - skipActiveTime[i];
            // Change tick range seconds inside
            _mockUniswapV3PoolSnapshot(lockupFarm, true, skipActiveTime[i]);
            uint256[][] memory rewardsForActiveLiquidity =
                UniV3ActiveLiquidityFarm(lockupFarm).computeRewards(currentActor, depositId);

            if (activeTime == 0) {
                for (uint256 j; j < rewardsForActiveLiquidity[0].length; j++) {
                    assertEq(rewardsForActiveLiquidity[0][j], 0);
                }
            } else {
                uint256 timesDifference = increaseTime / activeTime;
                for (uint256 j; j < rewardsForActiveLiquidity[0].length; j++) {
                    assertEq(rewards[0][j] / timesDifference, rewardsForActiveLiquidity[0][j]);
                }
            }
        }
    }

    function test_Withdraw_For_ActiveLiquidity(uint256 skipActiveTime) public depositSetup(nonLockupFarm, false) {
        uint256 increaseTime = 10 days;

        skipActiveTime = bound(skipActiveTime, 0 days, increaseTime);
        vm.assume(skipActiveTime % 5 days == 0);
        skip(increaseTime);
        vm.startPrank(user);

        uint256[][] memory rewards = UniV3ActiveLiquidityFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        uint256 activeTime = increaseTime - skipActiveTime;

        // Change tick range seconds inside
        uint256 secondsInside = _mockUniswapV3PoolSnapshot(nonLockupFarm, true, skipActiveTime);
        uint256[][] memory rewardsForActiveLiquidity =
            UniV3ActiveLiquidityFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(nonLockupFarm);
        emit IFarm.PoolUnsubscribed(depositId, COMMON_FUND_ID, rewardsForActiveLiquidity[0]);
        UniV3ActiveLiquidityFarm(nonLockupFarm).withdraw(depositId);
        if (activeTime == 0) {
            for (uint256 j; j < rewardsForActiveLiquidity[0].length; j++) {
                assertEq(rewardsForActiveLiquidity[0][j], 0);
            }
        } else {
            uint256 timesDifference = increaseTime / activeTime;
            for (uint256 j; j < rewardsForActiveLiquidity[0].length; j++) {
                assertEq(rewards[0][j] / timesDifference, rewardsForActiveLiquidity[0][j]);
            }
        }
        assertEq(UniV3ActiveLiquidityFarm(nonLockupFarm).lastSecondsInside(), secondsInside);
    }
}

abstract contract UniV3ActiveLiquidityFarmInheritTest is ActiveLiquidityTest {}
