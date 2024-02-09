// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {BaseUniV3Farm} from "../../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {Demeter_BaseUniV3FarmDeployer} from
    "../../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3FarmDeployer.sol";
import {INonfungiblePositionManager as INFPM} from
    "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../BaseUniV3Farm.t.sol";
import "../../../utils/UpgradeUtil.t.sol";

contract Demeter_SushiV3FarmTest is BaseUniV3FarmTest {
    // Define variables

    string public constant FARM_NAME = "Demeter_SushiV3_v1";
    Demeter_BaseUniV3FarmDeployer public sushiswapFarmDeployer;

    function setUp() public virtual override {
        super.setUp();

        NFPM = SUSHISWAP_NFPM;
        UNIV3_FACTORY = SUSHISWAP_FACTORY;
        SWAP_ROUTER = SUSHISWAP_SWAP_ROUTER;
        FARM_ID = FARM_NAME;

        vm.startPrank(PROXY_OWNER);
        address impl = address(new BaseUniV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        sushiswapFarmDeployer = new Demeter_BaseUniV3FarmDeployer(
            DEMETER_FACTORY, FARM_ID, UNIV3_FACTORY, NFPM, UNISWAP_UTILS, NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        factory.registerFarmDeployer(address(sushiswapFarmDeployer));

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

        invalidRewardToken = USDT;

        vm.stopPrank();

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
        Demeter_BaseUniV3FarmDeployer.FarmData memory _data = Demeter_BaseUniV3FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            uniswapPoolData: poolData,
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(sushiswapFarmDeployer), 1e22);
        address farm = sushiswapFarmDeployer.createFarm(_data);
        return farm;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt)
        public
        override
        useKnownActor(user)
        returns (uint256)
    {
        uint256 depositAmount1 = baseAmt * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = baseAmt * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(NFPM, depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(NFPM, depositAmount2);

        (uint256 tokenId, uint128 liquidity,,) = INFPM(NFPM).mint(
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
        return liquidity;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt, bytes memory revertMsg)
        public
        override
        useKnownActor(currentActor)
    {
        uint256 _baseAmt = baseAmt;
        if (baseAmt == 0) _baseAmt = 1e3;
        uint256 depositAmount1 = _baseAmt * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = _baseAmt * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(NFPM, depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(NFPM, depositAmount2);

        (uint256 tokenId, uint128 liquidity,,) = INFPM(NFPM).mint(
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
        BaseUniV3Farm(farm).onERC721Received(address(0), currentActor, tokenId, abi.encode(locked));
    }
}

contract Demeter_SushiV3FarmInheritTest is
    Demeter_SushiV3FarmTest,
    DepositTest,
    WithdrawTest,
    WithdrawWithExpiryTest,
    ClaimRewardsTest,
    GetRewardFundInfoTest,
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
    UpdateCoolDownPeriodTest,
    CloseFarmTest,
    _SetupFarmTest,
    InitializeTest,
    OnERC721ReceivedTest,
    WithdrawAdditionalTest,
    ClaimUniswapFeeTest,
    RecoverERC20Test
{
    function setUp() public override(Demeter_SushiV3FarmTest, BaseFarmTest) {
        super.setUp();
    }
}
