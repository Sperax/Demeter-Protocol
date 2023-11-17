// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../../contracts/uniswapV3/uniswap/Demeter_UniV3Farm.sol";
import "../../../contracts/uniswapV3/uniswap/Demeter_UniV3FarmDeployer.sol";
import {INonfungiblePositionManager as INFPM} from "../../../contracts/uniswapV3/interfaces/UniswapV3.sol";

// import tests
import "../../BaseFarm.t.sol";
import "../BaseUniV3Farm.t.sol";
import "../../utils/UpgradeUtil.t.sol";

contract Demeter_UniV3FarmTest is BaseUniV3FarmTest {
    // Define variables

    string public FARM_ID = "Demeter_UniV3_v4";
    Demeter_UniV3FarmDeployer public uniswapV3FarmDeployer;

    function setUp() public virtual override {
        super.setUp();

        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;

        vm.startPrank(PROXY_OWNER);
        address impl = address(new Demeter_UniV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        uniswapV3FarmDeployer = new Demeter_UniV3FarmDeployer(
            DEMETER_FACTORY
        );
        factory.registerFarmDeployer(address(uniswapV3FarmDeployer));

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
        Demeter_UniV3FarmDeployer.FarmData memory _data = Demeter_UniV3FarmDeployer.FarmData({
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
    function deposit(address farm, bool locked, uint256 baseAmt) public override useKnownActor(user) {
        uint256 depositAmount1 = baseAmt * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = baseAmt * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(Demeter_UniV3Farm(farm).NFPM(), depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(Demeter_UniV3Farm(farm).NFPM(), depositAmount2);

        (uint256 tokenId, uint128 liquidity,,) = INFPM(Demeter_UniV3Farm(farm).NFPM()).mint(
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

        vm.expectEmit(true, true, false, true);
        emit Deposited(currentActor, locked, tokenId, liquidity);
        IERC721(Demeter_UniV3Farm(farm).NFPM()).safeTransferFrom(currentActor, farm, tokenId, abi.encode(locked));
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
        IERC20(DAI).approve(Demeter_UniV3Farm(farm).NFPM(), depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(Demeter_UniV3Farm(farm).NFPM(), depositAmount2);

        (uint256 tokenId, uint128 liquidity,,) = INFPM(Demeter_UniV3Farm(farm).NFPM()).mint(
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
            INFPM(Demeter_UniV3Farm(farm).NFPM()).decreaseLiquidity(
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

contract FARM_IDTest is Demeter_UniV3FarmTest {
    function test_FARM_ID() public {
        string memory farmId = Demeter_UniV3Farm(farmProxy).FARM_ID();
        assertEq(farmId, FARM_ID);
    }
}

contract Demeter_UniV3FarmTestInheritTest is
    Demeter_UniV3FarmTest,
    DepositTest,
    WithdrawTest,
    ClaimRewardsTest,
    GetRewardFundInfoTest,
    InitiateCooldownTest,
    AddRewardsTest,
    SetRewardRateTest,
    GetRewardBalanceTest,
    GetNumSubscriptionsTest,
    SubscriptionInfoTest,
    UpdateTokenManagerTest,
    FarmPauseSwitchTest,
    UpdateFarmStartTimeTest,
    UpdateCoolDownPeriodTest,
    _SetupFarmTest,
    InitializeTest,
    OnERC721ReceivedTest,
    WithdrawAdditionalTest,
    ClaimUniswapFeeTest,
    MiscellaneousTest
{
    function setUp() public override(Demeter_UniV3FarmTest, BaseFarmTest) {
        super.setUp();
    }
}
