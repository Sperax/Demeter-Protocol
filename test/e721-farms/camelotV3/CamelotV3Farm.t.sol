// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@cryptoalgebra/v1.9-directional-fee-periphery/contracts/interfaces/ISwapRouter.sol";
import {
    E721Farm,
    CamelotV3Farm,
    CamelotPoolData,
    RewardTokenData,
    ICamelotV3Factory,
    ICamelotV3TickSpacing,
    INFPM,
    OperableDeposit,
    InitializeInput
} from "../../../contracts/e721-farms/camelotV3/CamelotV3Farm.sol";
import {ICamelotV3Utils} from "../../../contracts/e721-farms/camelotV3/interfaces/ICamelotV3Utils.sol";
import {
    ICamelotV3NFPMUtils,
    Position
} from "../../../contracts/e721-farms/camelotV3/interfaces/ICamelotV3NonfungiblePositionManagerUtils.sol";
import {ICamelotV3PoolState} from "../../../contracts/e721-farms/camelotV3/interfaces/ICamelotV3.sol";
import {CamelotV3FarmDeployer} from "../../../contracts/e721-farms/camelotV3/CamelotV3FarmDeployer.sol";
import {IFarmRegistry} from "../../../contracts/FarmRegistry.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// import tests
import {E721FarmTest, E721FarmInheritTest} from "../E721Farm.t.sol";
import {FarmTest, FarmInheritTest, IFarm} from "../../Farm.t.sol";
import {ExpirableFarmInheritTest} from "../../features/ExpirableFarm.t.sol";
import {UpgradeUtil} from "../../utils/UpgradeUtil.t.sol";

import {VmSafe} from "forge-std/Vm.sol";

// Note -> Important considerations.
// The tickspacing of pools is not immutable.

// If tickspacing is changed in a way that either our of tickUpper and tickLower are not divisible by this new tickspacing, users will not be able to mint new positions adhering to our farm ticks and they will also not be able to increase liquidity of their current positions.
// We can reduce risk by choosing tickLower and tickUpper as (highly divisible numbers and there should be more common divisors/factors between the two numbers) in our farm tick requirement. And ofcourse both the numbers should be divisible by the tickspacing of the pool at the time of farm launch.
// Camelot V3 pools can set tickspacing upto 500.

interface ICamelotV3FactoryTesting {
    function owner() external view returns (address);
}

interface ICamelotV3PoolTesting {
    function setTickSpacing(int24 newTickSpacing) external;
}

abstract contract CamelotV3FarmTest is E721FarmTest {
    string public FARM_NAME = "Demeter_CamelotV3_v1";
    int24 public TICK_LOWER = -887220;
    int24 public TICK_UPPER = 887220;
    address public NFPM;
    address public FACTORY;
    address public SWAP_ROUTER;
    string public FARM_ID;

    uint256 constant depositId = 1;
    CamelotV3FarmDeployer public camelotV3FarmDeployer;

    // Custom Errors
    error InvalidCamelotPoolConfig();
    error NoData();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();

    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function setUp() public virtual override {
        super.setUp();
        NFPM = CAMELOT_V3_NFPM;
        SWAP_ROUTER = CAMELOT_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        vm.startPrank(PROXY_OWNER);
        address impl = address(new CamelotV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        IFarmRegistry registry = IFarmRegistry(FARM_REGISTRY);
        camelotV3FarmDeployer = new CamelotV3FarmDeployer(
            FARM_REGISTRY,
            FARM_ID,
            CAMELOT_V3_FACTORY,
            NFPM,
            CAMELOT_V3_UTILS,
            CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        registry.registerFarmDeployer(address(camelotV3FarmDeployer));

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

        invalidRewardToken = USDT;

        vm.stopPrank();

        // Create and setup Farms
        lockupFarm = createFarm(block.timestamp, true);
        nonLockupFarm = createFarm(block.timestamp, false);
    }

    function generateRewardTokenData() public view returns (RewardTokenData[] memory rwdTokenData) {
        address[] memory rewardToken = rwdTokens;
        rwdTokenData = new RewardTokenData[](rewardToken.length);
        for (uint8 i = 0; i < rewardToken.length; ++i) {
            rwdTokenData[i] = RewardTokenData(rewardToken[i], currentActor);
        }
    }

    function _swap(address inputToken, address outputToken, uint256 amountIn) internal returns (uint256 amountOut) {
        deal(address(inputToken), currentActor, amountIn);

        IERC20(inputToken).approve(address(SWAP_ROUTER), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: inputToken,
            tokenOut: outputToken,
            recipient: currentActor,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            limitSqrtPrice: 0
        });
        // Executes the swap.
        amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function _simulateSwap() internal {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        _swap(DAI, USDCe, depositAmount1);
        _swap(USDCe, DAI, depositAmount2);
    }

    function createPosition(address from) public override returns (uint256 tokenId, address nftContract) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        deal(DAI, from, depositAmount1);
        IERC20(DAI).approve(nfpm(), depositAmount1);

        deal(USDCe, from, depositAmount2);
        IERC20(USDCe).approve(nfpm(), depositAmount2);

        (uint256 _tokenId,,,) = INFPM(nfpm()).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: from,
                deadline: block.timestamp
            })
        );
        return (_tokenId, nfpm());
    }

    function getLiquidity(uint256 tokenId) public view override returns (uint256 liquidity) {
        Position memory positions =
            ICamelotV3NFPMUtils(CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS).positions(nfpm(), tokenId);
        return uint256(positions.liquidity);
    }

    function createFarm(uint256 startTime, bool lockup)
        public
        virtual
        override
        useKnownActor(owner)
        returns (address)
    {
        RewardTokenData[] memory rwdTokenData = generateRewardTokenData();
        // Create Farm
        CamelotPoolData memory poolData =
            CamelotPoolData({tokenA: DAI, tokenB: USDCe, tickLowerAllowed: TICK_LOWER, tickUpperAllowed: TICK_UPPER});
        CamelotV3FarmDeployer.FarmData memory _data = CamelotV3FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD_DAYS : 0,
            camelotPoolData: poolData,
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(camelotV3FarmDeployer), 1e22);
        address farm = camelotV3FarmDeployer.createFarm(_data);
        return farm;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt) public virtual override returns (uint256) {
        (uint256 tokenId, uint256 liquidity) = _mintPosition(baseAmt, user);
        vm.startPrank(user);
        IERC721(NFPM).safeTransferFrom(currentActor, farm, tokenId, abi.encode(locked));
        vm.stopPrank();
        return liquidity;
    }

    /// @notice Farm specific deposit logic
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
                    liquidity: SafeCast.toUint128(liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        }

        vm.expectRevert(revertMsg);
        changePrank(NFPM);
        // This will not actually deposit, but this is enough to check for the reverts
        E721Farm(farm).onERC721Received(address(0), currentActor, tokenId, abi.encode(locked));
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

    function nfpm() internal view override returns (address) {
        return NFPM;
    }
}

abstract contract InitializeTest is CamelotV3FarmTest {
    function test_Initialize_RevertWhen_InvalidTickRange() public {
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: 0,
            farmRegistry: FARM_REGISTRY,
            camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            camelotV3Factory: CAMELOT_V3_FACTORY,
            nftContract: NFPM,
            camelotUtils: CAMELOT_V3_UTILS,
            nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        address camelotPool = ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe);
        int24 spacing = ICamelotV3TickSpacing(camelotPool).tickSpacing();

        // Fails for _tickLower >= _tickUpper
        input.camelotPoolData.tickUpperAllowed = TICK_LOWER;
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({_input: input});
        input.camelotPoolData.tickUpperAllowed = TICK_UPPER; // reset

        // Fails for _tickLower < -887272
        input.camelotPoolData.tickLowerAllowed = -887272 - 1;
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({_input: input});
        input.camelotPoolData.tickLowerAllowed = TICK_LOWER; // reset

        if (spacing > 1) {
            // Fails for _tickLower % spacing != 0
            input.camelotPoolData.tickLowerAllowed = -887271;
            vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
            CamelotV3Farm(farmProxy).initialize({_input: input});
            input.camelotPoolData.tickLowerAllowed = TICK_LOWER; // reset

            // Fails for _tickUpper % spacing != 0
            input.camelotPoolData.tickUpperAllowed = 887271;
            vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
            CamelotV3Farm(farmProxy).initialize({_input: input});
            input.camelotPoolData.tickUpperAllowed = TICK_UPPER; // reset
        }

        // Fails for _tickUpper > 887272
        input.camelotPoolData.tickUpperAllowed = 887272 + 1;
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({_input: input});
        input.camelotPoolData.tickUpperAllowed = TICK_UPPER; // reset
    }

    function test_Initialize_RevertWhen_InvalidCamelotPoolConfig() public {
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: 0,
            farmRegistry: FARM_REGISTRY,
            camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            camelotV3Factory: CAMELOT_V3_FACTORY,
            nftContract: NFPM,
            camelotUtils: CAMELOT_V3_UTILS,
            nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
        CamelotV3Farm(farmProxy).initialize({_input: input});
    }

    function test_initialize() public {
        address camelotPool = ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe);
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: COOLDOWN_PERIOD_DAYS,
            farmRegistry: FARM_REGISTRY,
            camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            camelotV3Factory: CAMELOT_V3_FACTORY,
            nftContract: NFPM,
            camelotUtils: CAMELOT_V3_UTILS,
            nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
        CamelotV3Farm(farmProxy).initialize({_input: input});

        assertEq(CamelotV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(CamelotV3Farm(farmProxy).tickLowerAllowed(), TICK_LOWER);
        assertEq(CamelotV3Farm(farmProxy).tickUpperAllowed(), TICK_UPPER);
        assertEq(CamelotV3Farm(farmProxy).camelotPool(), camelotPool);
        assertEq(CamelotV3Farm(farmProxy).owner(), address(this)); // changes to admin when called via deployer
        assertEq(CamelotV3Farm(farmProxy).farmStartTime(), block.timestamp);
        assertEq(CamelotV3Farm(farmProxy).lastFundUpdateTime(), 0);
        assertEq(CamelotV3Farm(farmProxy).cooldownPeriod(), COOLDOWN_PERIOD_DAYS * 1 days);
        assertEq(CamelotV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(CamelotV3Farm(farmProxy).camelotV3Factory(), CAMELOT_V3_FACTORY);
        assertEq(CamelotV3Farm(farmProxy).nftContract(), NFPM);
        assertEq(CamelotV3Farm(farmProxy).camelotUtils(), CAMELOT_V3_UTILS);
        assertEq(CamelotV3Farm(farmProxy).nfpmUtils(), CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS);
    }
}

abstract contract OnERC721ReceivedTest is CamelotV3FarmTest {
    function _mintHelper(address token0, address token1, int24 tickLower, int24 tickUpper)
        internal
        returns (uint256 tokenId)
    {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(token0).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(token1).decimals();

        deal(token0, currentActor, depositAmount1);
        IERC20(token0).approve(NFPM, depositAmount1);

        deal(token1, currentActor, depositAmount2);
        IERC20(token1).approve(NFPM, depositAmount2);

        (tokenId,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: token0,
                token1: token1,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );
    }

    function test_OnERC721Received_RevertWhen_IncorrectPoolToken() public useKnownActor(user) {
        uint256 tokenId = _mintHelper(DAI, USDT, TICK_LOWER, TICK_UPPER);

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.IncorrectPoolToken.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId, abi.encode(true));
    }

    function test_OnERC721Received_RevertWhen_IncorrectTickRange() public useKnownActor(user) {
        int24 spacing =
            ICamelotV3TickSpacing(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).tickSpacing();

        uint256 tokenId1 = _mintHelper(DAI, USDCe, TICK_LOWER + spacing, TICK_UPPER);

        uint256 tokenId2 = _mintHelper(DAI, USDCe, TICK_LOWER, TICK_UPPER - spacing);

        uint256 tokenId3 = _mintHelper(DAI, USDCe, TICK_LOWER + spacing, TICK_UPPER - spacing);

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId1, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId2, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId3, abi.encode(true));
    }
}

abstract contract ClaimCamelotFeeTest is CamelotV3FarmTest {
    function test_ClaimCamelotFee_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        IFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsClosed.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(0);
    }

    function test_ClaimCamelotFee_RevertWhen_DepositDoesNotExist_during_claimCamelotFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(0);
    }

    function test_ClaimCamelotFee_RevertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.NoFeeToClaim.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(depositId);
    }

    function test_claimCamelotFee() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = CamelotV3Farm(lockupFarm).depositToTokenId(depositId);

        vm.expectEmit(true, false, false, false, address(lockupFarm)); // for now ignoring amount0 and amount1
        emit CamelotV3Farm.PoolFeeCollected(currentActor, _tokenId, 0, 0);

        vm.recordLogs();

        uint256 balance0Before = IERC20(DAI).balanceOf(user);
        uint256 balance1Before = IERC20(USDCe).balanceOf(user);

        CamelotV3Farm(lockupFarm).claimCamelotFee(depositId);

        uint256 balance0After = IERC20(DAI).balanceOf(user);
        uint256 balance1After = IERC20(USDCe).balanceOf(user);

        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        uint256 amt0;
        uint256 amt1;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == bytes32(keccak256("PoolFeeCollected(address,uint256,uint256,uint256)"))) {
                (, uint256 _amt0, uint256 _amt1) = abi.decode(entries[i].data, (uint256, uint256, uint256));
                amt0 = _amt0;
                amt1 = _amt1;
                break;
            }
        }

        assertEq(balance0After, amt0 + balance0Before);
        assertEq(balance1After, amt1 + balance1Before);
    }

    function testFuzz_claimCamelotFee_tickSpacingChanged(int24 newTickSpacing)
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        int24 currentTickSpacing =
            ICamelotV3TickSpacing(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).tickSpacing();

        vm.assume(newTickSpacing >= 1 && newTickSpacing <= 500 && newTickSpacing != currentTickSpacing);

        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = CamelotV3Farm(lockupFarm).depositToTokenId(depositId);

        address camelotFactoryOwner = ICamelotV3FactoryTesting(CAMELOT_V3_FACTORY).owner();
        vm.startPrank(camelotFactoryOwner);
        ICamelotV3PoolTesting(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).setTickSpacing(
            newTickSpacing
        );
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(true, false, false, false, address(lockupFarm)); // for now ignoring amount0 and amount1
        emit CamelotV3Farm.PoolFeeCollected(currentActor, _tokenId, 0, 0);

        CamelotV3Farm(lockupFarm).claimCamelotFee(depositId);
    }
}

abstract contract IncreaseDepositTest is CamelotV3FarmTest {
    // TODO -> Checking difference between actualLiquidity and liquidity
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint128 actualLiquidity,
        uint256 amount0,
        uint256 amount1,
        address pool
    );
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function test_IncreaseDeposit_RevertWhen_FarmIsInactive() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        CamelotV3Farm(lockupFarm).farmPauseSwitch(true);

        uint256 deposit0 = DEPOSIT_AMOUNT * 10 ** ERC20(DAI).decimals();
        uint256 deposit1 = DEPOSIT_AMOUNT * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [deposit0, deposit1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, user, deposit0);
        deal(USDCe, user, deposit1);
        vm.startPrank(user);

        IERC20(DAI).approve(lockupFarm, deposit0);
        IERC20(USDCe).approve(lockupFarm, deposit1);

        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsInactive.selector));
        CamelotV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        CamelotV3Farm(lockupFarm).increaseDeposit(depositId, [DEPOSIT_AMOUNT, DEPOSIT_AMOUNT], [uint256(0), uint256(0)]);
    }

    function test_IncreaseDeposit_RevertWhen_InvalidAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidAmount.selector));
        CamelotV3Farm(lockupFarm).increaseDeposit(depositId, [uint256(0), uint256(0)], [uint256(0), uint256(0)]);
    }

    function test_IncreaseDeposit_RevertWhen_DepositIsInCooldown()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 deposit0 = DEPOSIT_AMOUNT * 10 ** ERC20(DAI).decimals();
        uint256 deposit1 = DEPOSIT_AMOUNT * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [deposit0, deposit1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, currentActor, deposit0);
        deal(USDCe, currentActor, deposit1);
        IERC20(DAI).approve(lockupFarm, deposit0);
        IERC20(USDCe).approve(lockupFarm, deposit1);

        CamelotV3Farm(lockupFarm).initiateCooldown(depositId);
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositIsInCooldown.selector));
        CamelotV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function testFuzz_IncreaseDeposit(bool lockup, uint256 _depositAmount) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, lockup);

        _depositAmount = bound(_depositAmount, 1, 1e7);
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = CamelotV3Farm(farm).depositToTokenId(depositId);
        uint256 depositAmount0 = _depositAmount * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount1 = _depositAmount * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [depositAmount0, depositAmount1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, currentActor, depositAmount0);
        deal(USDCe, currentActor, depositAmount1);
        IERC20(DAI).approve(farm, depositAmount0);
        IERC20(USDCe).approve(farm, depositAmount1);

        uint256 oldLiquidity = CamelotV3Farm(farm).getDepositInfo(depositId).liquidity;
        uint256[2] memory oldTotalFundLiquidity = [
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            lockup ? CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity : 0
        ];

        // TODO wanted to check for transfer events but solidity does not support two definitions for the same event
        vm.expectEmit(DAI);
        emit Approval(farm, NFPM, depositAmount0);
        vm.expectEmit(USDCe);
        emit Approval(farm, NFPM, depositAmount1);
        vm.expectEmit(true, false, false, false, NFPM);
        emit IncreaseLiquidity(tokenId, 0, 0, 0, 0, address(0));
        vm.expectEmit(true, false, false, false, farm);
        emit OperableDeposit.DepositIncreased(depositId, 0);

        vm.recordLogs();
        CamelotV3Farm(farm).increaseDeposit(depositId, amounts, minAmounts);
        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        // TODO -> Checking difference between actualLiquidity and liquidity emitted in IncreaseLiquidity.
        // uint128 loggedLiquidity;
        uint128 loggedActualLiquidity;
        uint256 loggedAmount0;
        uint256 loggedAmount1;
        bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("IncreaseLiquidity(uint256,uint128,uint128,uint256,uint256,address)"))
            {
                (, loggedActualLiquidity, loggedAmount0, loggedAmount1,) =
                    abi.decode(entries[i].data, (uint128, uint128, uint256, uint256, address));
            }
            if (entries[i].topics[0] == keccak256("DepositIncreased(uint256,uint256)")) {
                assertEq(
                    abi.decode(entries[i].data, (uint256)),
                    loggedActualLiquidity,
                    "DepositIncreased event should have the same liquidity as IncreaseLiquidity event"
                );
                found = true;
            }
        }
        assertTrue(found, "DepositIncreased event not found");
        assertEq(IERC20(DAI).balanceOf(currentActor), depositAmount0 - loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), depositAmount1 - loggedAmount1);
        assertEq(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity + loggedActualLiquidity);
        assertEq(
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldTotalFundLiquidity[0] + loggedActualLiquidity
        );
        lockup
            ? assertEq(
                CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity,
                oldTotalFundLiquidity[0] + loggedActualLiquidity
            )
            : assert(true);
    }
}

abstract contract DecreaseDepositTest is CamelotV3FarmTest {
    uint128 constant dummyLiquidityToWithdraw = 1;

    function test_DecreaseDeposit_RevertWhen_FarmIsClosed() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        CamelotV3Farm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsClosed.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_CannotWithdrawZeroAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(IFarm.CannotWithdrawZeroAmount.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, 0, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    // Decrease deposit test is always for non-lockup deposit.
    function testFuzz_DecreaseDeposit(bool isLockupFarm, uint256 _liquidityToWithdraw) public {
        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);
        skip(1);

        uint128 oldLiquidity = SafeCast.toUint128(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = SafeCast.toUint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = CamelotV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        CamelotV3Farm(farm).claimRewards(depositId);
        IERC20(DAI).transfer(makeAddr("Random"), IERC20(DAI).balanceOf(currentActor));
        IERC20(USDCe).transfer(makeAddr("Random"), IERC20(USDCe).balanceOf(currentActor));

        vm.expectEmit(farm);
        emit OperableDeposit.DepositDecreased(depositId, liquidityToWithdraw);
        vm.expectEmit(true, false, false, false, NFPM);
        emit DecreaseLiquidity(tokenId, 0, 0, 0);

        vm.recordLogs();
        CamelotV3Farm(farm).decreaseDeposit(depositId, liquidityToWithdraw, minAmounts);
        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        uint128 loggedLiquidity;
        uint256 loggedAmount0;
        uint256 loggedAmount1;
        bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DecreaseLiquidity(uint256,uint128,uint256,uint256)")) {
                (loggedLiquidity, loggedAmount0, loggedAmount1) =
                    abi.decode(entries[i].data, (uint128, uint256, uint256));
                found = true;
            }
        }
        assertTrue(found, "DecreaseLiquidity event not found");
        assertEq(loggedLiquidity, liquidityToWithdraw);
        assertEq(IERC20(DAI).balanceOf(currentActor), loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), loggedAmount1);
        assertEq(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
    }

    function testFuzz_DecreaseDeposit_tickSpacingChanged(
        bool isLockupFarm,
        uint256 _liquidityToWithdraw,
        int24 newTickSpacing
    ) public {
        int24 currentTickSpacing =
            ICamelotV3TickSpacing(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).tickSpacing();

        vm.assume(newTickSpacing >= 1 && newTickSpacing <= 500 && newTickSpacing != currentTickSpacing);

        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);
        skip(1);

        uint128 oldLiquidity = SafeCast.toUint128(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = SafeCast.toUint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = CamelotV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        CamelotV3Farm(farm).claimRewards(depositId);
        IERC20(DAI).transfer(makeAddr("Random"), IERC20(DAI).balanceOf(currentActor));
        IERC20(USDCe).transfer(makeAddr("Random"), IERC20(USDCe).balanceOf(currentActor));
        vm.stopPrank();

        address camelotFactoryOwner = ICamelotV3FactoryTesting(CAMELOT_V3_FACTORY).owner();
        vm.startPrank(camelotFactoryOwner);
        ICamelotV3PoolTesting(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).setTickSpacing(
            newTickSpacing
        );
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(farm);
        emit OperableDeposit.DepositDecreased(depositId, liquidityToWithdraw);
        vm.expectEmit(true, false, false, false, NFPM);
        emit DecreaseLiquidity(tokenId, 0, 0, 0);

        vm.recordLogs();
        CamelotV3Farm(farm).decreaseDeposit(depositId, liquidityToWithdraw, minAmounts);
        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        uint128 loggedLiquidity;
        uint256 loggedAmount0;
        uint256 loggedAmount1;
        bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DecreaseLiquidity(uint256,uint128,uint256,uint256)")) {
                (loggedLiquidity, loggedAmount0, loggedAmount1) =
                    abi.decode(entries[i].data, (uint128, uint256, uint256));
                found = true;
            }
        }
        assertTrue(found, "DecreaseLiquidity event not found");
        assertEq(loggedLiquidity, liquidityToWithdraw);
        assertEq(IERC20(DAI).balanceOf(currentActor), loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), loggedAmount1);
        assertEq(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
    }
}

abstract contract GetTokenAmountsTest is CamelotV3FarmTest {
    function test_getTokenAmounts() public depositSetup(lockupFarm, true) {
        // Manual testing
        address[] memory tokens;
        uint256[] memory amounts;
        (tokens, amounts) = CamelotV3Farm(lockupFarm).getTokenAmounts();

        (uint160 sqrtRatioX96,,,,,,,) = ICamelotV3PoolState(CamelotV3Farm(lockupFarm).camelotPool()).globalState();

        uint256[] memory expectedAmounts = new uint256[](2);

        (expectedAmounts[0], expectedAmounts[1]) = ICamelotV3Utils(CAMELOT_V3_UTILS).getAmountsForLiquidity(
            sqrtRatioX96,
            CamelotV3Farm(lockupFarm).tickLowerAllowed(),
            CamelotV3Farm(lockupFarm).tickUpperAllowed(),
            SafeCast.toUint128(
                CamelotV3Farm(lockupFarm).getRewardFundInfo(CamelotV3Farm(lockupFarm).COMMON_FUND_ID()).totalLiquidity
            )
        );

        address camelotPool = CamelotV3Farm(lockupFarm).camelotPool();

        address[] memory expectedTokens = new address[](2);

        expectedTokens[0] = ICamelotV3PoolState(camelotPool).token0();
        expectedTokens[1] = ICamelotV3PoolState(camelotPool).token1();

        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i], expectedTokens[i]);
            assertEq(amounts[i], expectedAmounts[i]);
        }
    }
}

contract CamelotV3FarmInheritTest is
    InitializeTest,
    OnERC721ReceivedTest,
    ClaimCamelotFeeTest,
    IncreaseDepositTest,
    DecreaseDepositTest,
    FarmInheritTest,
    ExpirableFarmInheritTest,
    E721FarmInheritTest,
    GetTokenAmountsTest
{
    function setUp() public override(CamelotV3FarmTest, FarmTest) {
        super.setUp();
    }
}
