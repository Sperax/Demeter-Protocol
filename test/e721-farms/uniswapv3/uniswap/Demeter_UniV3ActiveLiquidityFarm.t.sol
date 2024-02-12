// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {BaseUniV3ActiveLiquidityFarm} from "../../../../contracts/e721-farms/uniswapV3/BaseUniV3ActiveLiquidityFarm.sol";
import {Demeter_BaseUniV3ActiveLiquidityDeployer} from
    "../../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3ActiveLiquidityDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../BaseUniV3ActiveLiquidityFarm.t.sol";
import "../../../utils/UpgradeUtil.t.sol";

contract Demeter_UniV3ActiveLiquidityFarmTest is BaseUniV3ActiveLiquidityFarmTest {
    // Define variables

    string public FARM_NAME = "Demeter_UniV3_v4";
    Demeter_BaseUniV3ActiveLiquidityDeployer public uniswapV3FarmDeployer;

    function setUp() public virtual override {
        super.setUp();

        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;

        vm.startPrank(PROXY_OWNER);
        address impl = address(new BaseUniV3ActiveLiquidityFarm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        uniswapV3FarmDeployer = new Demeter_BaseUniV3ActiveLiquidityDeployer(
            DEMETER_FACTORY, FARM_ID, UNIV3_FACTORY, NFPM, UNISWAP_UTILS, NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        factory.registerFarmDeployer(address(uniswapV3FarmDeployer));

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

        invalidRewardToken = USDT;

        vm.stopPrank();

        // Mint a position to ensure that tick ranges is initialized
        _mintPosition(1, makeAddr("RANDOM-USER-DEPOSIT"));

        // Create and setup Farms
        lockupFarm = createFarm(block.timestamp, true);
        nonLockupFarm = createFarm(block.timestamp, false);
    }

    function createFarm(uint256 startTime, bool lockup) public override useKnownActor(owner) returns (address) {
        RewardTokenData[] memory rwdTokenData = generateRewardTokenData();
        // Create Farm
        UniswapPoolData memory poolData = UniswapPoolData({
            tokenA: DAI,
            tokenB: USDCe,
            feeTier: FEE_TIER,
            tickLowerAllowed: TICK_LOWER,
            tickUpperAllowed: TICK_UPPER
        });
        Demeter_BaseUniV3ActiveLiquidityDeployer.FarmData memory _data = Demeter_BaseUniV3ActiveLiquidityDeployer
            .FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            uniswapPoolData: poolData,
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(uniswapV3FarmDeployer), 1e22);
        address farm = uniswapV3FarmDeployer.createFarm(_data);
        return farm;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt) public override returns (uint256) {
        currentActor = user;
        (uint256 tokenId, uint128 liquidity) = _mintPosition(baseAmt, currentActor);
        vm.startPrank(user);

        if (!locked) {
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, 0);
        } else {
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, 0);
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, 1);
        }
        vm.expectEmit(address(farm));
        emit Deposited(BaseFarm(farm).totalDeposits() + 1, currentActor, locked, liquidity);
        IERC721(NFPM).safeTransferFrom(currentActor, farm, tokenId, abi.encode(locked));
        vm.stopPrank();
        return liquidity;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt, bytes memory revertMsg) public override {
        uint256 _baseAmt = baseAmt;
        if (baseAmt == 0) _baseAmt = 1e3;
        currentActor = user;
        (uint256 tokenId, uint128 liquidity) = _mintPosition(_baseAmt, currentActor);
        vm.startPrank(user);

        if (baseAmt == 0) {
            // Decreasing liquidity to zero.
            INFPM(NFPM).decreaseLiquidity(
                INFPM.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: uint128(liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        }

        vm.expectRevert(revertMsg);
        changePrank(NFPM);
        // This will not actually deposit, but this is enough to check for the reverts
        BaseUniV3ActiveLiquidityFarm(farm).onERC721Received(address(0), currentActor, tokenId, abi.encode(locked));
    }

    function _mintPosition(uint256 _baseAmt, address _actor)
        internal
        useKnownActor(_actor)
        returns (uint256 tokenId, uint128 liquidity)
    {
        uint256 depositAmount1 = _baseAmt * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = _baseAmt * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(NFPM, depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(NFPM, depositAmount2);

        (tokenId, liquidity,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                fee: FEE_TIER,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );
    }
}

contract Demeter_UniV3FarmTestInheritTest is
    Demeter_UniV3ActiveLiquidityFarmTest,
    DepositTest,
    WithdrawTest,
    WithdrawWithExpiryTest,
    ClaimRewardsTest,
    GetRewardFundInfoTest,
    RecoverERC20Test,
    InitiateCooldownTest,
    AddRewardsTest,
    SetRewardRateTest,
    GetRewardBalanceTest,
    GetNumSubscriptionsTest,
    SubscriptionInfoTest,
    UpdateRewardTokenDataTest,
    FarmPauseSwitchTest,
    UpdateFarmStartTimeTest,
    UpdateFarmStartTimeWithExpiryTest,
    ExtendFarmDurationTest,
    CloseFarmTest,
    UpdateCoolDownPeriodTest,
    _SetupFarmTest,
    ActiveLiquidityTest
{
    function setUp() public override(Demeter_UniV3ActiveLiquidityFarmTest, BaseFarmTest) {
        super.setUp();
    }
}
