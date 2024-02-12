// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../../contracts/e721-farms/uniswapV3/BaseUniV3ActiveLiquidityFarm.sol";
import "../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import "../../BaseFarm.t.sol";
import "../../features/BaseFarmWithExpiry.t.sol";
import {VmSafe} from "forge-std/Vm.sol";

abstract contract BaseUniV3ActiveLiquidityFarmTest is BaseFarmTest {
    uint24 public FEE_TIER = 100;
    int24 public TICK_LOWER = -887270;
    int24 public TICK_UPPER = 887270;
    address public NFPM;
    address public UNIV3_FACTORY;
    address public SWAP_ROUTER;
    string public FARM_ID;

    uint256 constant depositId = 1;

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidUniswapPoolConfig();
    error NotAUniV3NFT();
    error NoData();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();

    function generateRewardTokenData() public view returns (RewardTokenData[] memory rwdTokenData) {
        address[] memory rewardToken = rwdTokens;
        rwdTokenData = new RewardTokenData[](rewardToken.length);
        for (uint8 i = 0; i < rewardToken.length; ++i) {
            rwdTokenData[i] = RewardTokenData(rewardToken[i], currentActor);
        }
    }

    function _swap(address inputToken, address outputToken, uint24 poolFee, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        deal(address(inputToken), currentActor, amountIn);

        IERC20(inputToken).approve(address(SWAP_ROUTER), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: inputToken,
            tokenOut: outputToken,
            fee: poolFee,
            recipient: currentActor,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        // Executes the swap.
        amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function _simulateSwap() internal {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        _swap(DAI, USDCe, FEE_TIER, depositAmount1);
        _swap(USDCe, DAI, FEE_TIER, depositAmount2);
    }

    function _mockUniswapV3PoolTick(address farm, bool _shouldMock) internal {
        address uniswapPool = BaseUniV3ActiveLiquidityFarm(farm).uniswapPool();
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
        address uniswapPool = BaseUniV3ActiveLiquidityFarm(farm).uniswapPool();
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
abstract contract ActiveLiquidityTest is BaseUniV3ActiveLiquidityFarmTest {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function test_IsFarmActive_When_InactiveLiquidity() public {
        // Assuming farm is always in active liquidity as tick range is huge.
        assertTrue(BaseUniV3ActiveLiquidityFarm(lockupFarm).isFarmActive());
        _mockUniswapV3PoolTick(lockupFarm, true);
        assertFalse(BaseUniV3ActiveLiquidityFarm(lockupFarm).isFarmActive());

        // Functions dependent on isFarmActive should revert.
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsInactive.selector));
        BaseUniV3ActiveLiquidityFarm(lockupFarm).initiateCooldown(1); // bogus depositId
    }

    function test_Withdraw_When_InactiveLiquidity() public depositSetup(lockupFarm, true) {
        vm.startPrank(user);
        uint256 depositId = 1;
        _mockUniswapV3PoolTick(lockupFarm, true);
        vm.expectEmit(NFPM);
        emit Transfer(lockupFarm, currentActor, BaseUniV3ActiveLiquidityFarm(lockupFarm).depositToTokenId(depositId));

        BaseUniV3ActiveLiquidityFarm(lockupFarm).withdraw(depositId);
    }

    function test_ComputeRewards_For_ActiveLiquidity() public depositSetup(lockupFarm, true) {
        uint256 increaseTime = 10 days;
        uint24[3] memory skipActiveTime = [0, 5 days, 10 days];
        skip(increaseTime);
        uint256[][] memory rewards = BaseUniV3ActiveLiquidityFarm(lockupFarm).computeRewards(currentActor, depositId);

        for (uint256 i; i < skipActiveTime.length; i++) {
            vm.clearMockedCalls();
            uint256 activeTime = increaseTime - skipActiveTime[i];
            // Change tick range seconds inside
            _mockUniswapV3PoolSnapshot(lockupFarm, true, skipActiveTime[i]);
            uint256[][] memory rewardsForActiveLiquidity =
                BaseUniV3ActiveLiquidityFarm(lockupFarm).computeRewards(currentActor, depositId);

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

        uint256[][] memory rewards = BaseUniV3ActiveLiquidityFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        uint256 activeTime = increaseTime - skipActiveTime;

        // Change tick range seconds inside
        uint256 secondsInside = _mockUniswapV3PoolSnapshot(nonLockupFarm, true, skipActiveTime);
        uint256[][] memory rewardsForActiveLiquidity =
            BaseUniV3ActiveLiquidityFarm(nonLockupFarm).computeRewards(currentActor, depositId);
        vm.expectEmit(nonLockupFarm);
        emit PoolUnsubscribed(depositId, 0, rewardsForActiveLiquidity[0]);
        BaseUniV3ActiveLiquidityFarm(nonLockupFarm).withdraw(depositId);
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

        assertEq(BaseUniV3ActiveLiquidityFarm(nonLockupFarm).lastSecondsInside(), secondsInside);
    }
}
