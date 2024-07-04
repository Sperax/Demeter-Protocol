// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {
    E721Farm,
    UniV3Farm,
    UniswapPoolData,
    RewardTokenData,
    IUniswapV3Factory,
    IUniswapV3TickSpacing,
    INFPM,
    OperableDeposit,
    ClaimableFee,
    InitializeInput
} from "../../../contracts/e721-farms/uniswapV3/UniV3Farm.sol";
import {IUniswapV3Utils} from "../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3Utils.sol";
import {
    INFPMUtils,
    Position
} from "../../../contracts/e721-farms/uniswapV3/interfaces/INonfungiblePositionManagerUtils.sol";
import {UniV3FarmDeployer} from "../../../contracts/e721-farms/uniswapV3/UniV3FarmDeployer.sol";
import {IFarmRegistry} from "../../../contracts/FarmRegistry.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// import tests
import {E721FarmTest, E721FarmInheritTest} from "../E721Farm.t.sol";
import {FarmTest, FarmInheritTest, IFarm} from "../../Farm.t.sol";
import {ExpirableFarmInheritTest} from "../../features/ExpirableFarm.t.sol";

import {E721FarmTest} from "../E721Farm.t.sol";
import {IFarm} from "../../Farm.t.sol";
import {UpgradeUtil} from "../../utils/UpgradeUtil.t.sol";

import {VmSafe} from "forge-std/Vm.sol";

abstract contract UniV3FarmTest is E721FarmTest {
    uint8 public FEE_TIER = 100;
    int24 public TICK_LOWER = -887270;
    int24 public TICK_UPPER = 887270;
    address public NFPM;
    address public UNIV3_FACTORY;
    address public SWAP_ROUTER;
    string public FARM_ID;

    uint256 constant depositId = 1;
    UniV3FarmDeployer public uniV3FarmDeployer;

    // Custom Errors
    error InvalidUniswapPoolConfig();
    error NoData();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(PROXY_OWNER);
        address impl = address(new UniV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        IFarmRegistry registry = IFarmRegistry(FARM_REGISTRY);
        uniV3FarmDeployer = new UniV3FarmDeployer(
            FARM_REGISTRY, FARM_ID, UNIV3_FACTORY, NFPM, UNISWAP_UTILS, NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        registry.registerFarmDeployer(address(uniV3FarmDeployer));

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
                fee: FEE_TIER,
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
        Position memory positions = INFPMUtils(NONFUNGIBLE_POSITION_MANAGER_UTILS).positions(nfpm(), tokenId);
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
        UniswapPoolData memory poolData = UniswapPoolData({
            tokenA: DAI,
            tokenB: USDCe,
            feeTier: FEE_TIER,
            tickLowerAllowed: TICK_LOWER,
            tickUpperAllowed: TICK_UPPER
        });
        UniV3FarmDeployer.FarmData memory _data = UniV3FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD_DAYS : 0,
            uniswapPoolData: poolData,
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(uniV3FarmDeployer), 1e22);
        address farm = uniV3FarmDeployer.createFarm(_data);
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

    function nfpm() internal view override returns (address) {
        return NFPM;
    }
}

abstract contract InitializeTest is UniV3FarmTest {
    function test_Initialize_RevertWhen_InvalidTickRange() public {
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: COOLDOWN_PERIOD_DAYS,
            farmRegistry: FARM_REGISTRY,
            uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            uniV3Factory: UNIV3_FACTORY,
            nftContract: NFPM,
            uniswapUtils: UNISWAP_UTILS,
            nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        int24 spacing = IUniswapV3TickSpacing(uniswapPool).tickSpacing();

        // Fails for _tickLower >= _tickUpper
        input.uniswapPoolData.tickUpperAllowed = TICK_LOWER;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidTickRange.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.tickUpperAllowed = TICK_UPPER;

        // Fails for _tickLower < -887272
        input.uniswapPoolData.tickLowerAllowed = -887273;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidTickRange.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.tickLowerAllowed = TICK_LOWER;

        if (spacing > 1) {
            // Fails for _tickLower % spacing != 0
            input.uniswapPoolData.tickLowerAllowed = -887271;
            vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidTickRange.selector));
            UniV3Farm(farmProxy).initialize({_input: input});
            input.uniswapPoolData.tickLowerAllowed = TICK_LOWER;

            // Fails for _tickUpper % spacing != 0
            input.uniswapPoolData.tickUpperAllowed = 887271;
            vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidTickRange.selector));
            UniV3Farm(farmProxy).initialize({_input: input});
            input.uniswapPoolData.tickUpperAllowed = TICK_UPPER;
        }

        // Fails for _tickUpper > 887272
        input.uniswapPoolData.tickUpperAllowed = 887273;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidTickRange.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.tickUpperAllowed = TICK_UPPER;
    }

    function test_Initialize_RevertWhen_InvalidUniswapPoolConfig() public {
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: COOLDOWN_PERIOD_DAYS,
            farmRegistry: FARM_REGISTRY,
            uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            uniV3Factory: UNIV3_FACTORY,
            nftContract: NFPM,
            uniswapUtils: UNISWAP_UTILS,
            nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
        input.uniswapPoolData.tokenA = USDCe;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidUniswapPoolConfig.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.tokenA = DAI;

        input.uniswapPoolData.tokenB = DAI;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidUniswapPoolConfig.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.tokenB = USDCe;

        input.uniswapPoolData.feeTier = FEE_TIER + 1;
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidUniswapPoolConfig.selector));
        UniV3Farm(farmProxy).initialize({_input: input});
        input.uniswapPoolData.feeTier = FEE_TIER;
    }

    function test_Initialize() public {
        InitializeInput memory input = InitializeInput({
            farmId: FARM_ID,
            farmStartTime: block.timestamp,
            cooldownPeriod: COOLDOWN_PERIOD_DAYS,
            farmRegistry: FARM_REGISTRY,
            uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            rwdTokenData: generateRewardTokenData(),
            uniV3Factory: UNIV3_FACTORY,
            nftContract: NFPM,
            uniswapUtils: UNISWAP_UTILS,
            nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        UniV3Farm(farmProxy).initialize({_input: input});

        assertEq(UniV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(UniV3Farm(farmProxy).tickLowerAllowed(), TICK_LOWER);
        assertEq(UniV3Farm(farmProxy).tickUpperAllowed(), TICK_UPPER);
        assertEq(UniV3Farm(farmProxy).uniswapPool(), uniswapPool);
        assertEq(UniV3Farm(farmProxy).owner(), address(this)); // changes to admin when called via deployer
        assertEq(UniV3Farm(farmProxy).farmStartTime(), block.timestamp);
        assertEq(UniV3Farm(farmProxy).lastFundUpdateTime(), 0);
        assertEq(UniV3Farm(farmProxy).cooldownPeriod(), COOLDOWN_PERIOD_DAYS * 1 days);
        assertEq(UniV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(UniV3Farm(farmProxy).uniV3Factory(), UNIV3_FACTORY);
        assertEq(UniV3Farm(farmProxy).nftContract(), NFPM);
        assertEq(UniV3Farm(farmProxy).uniswapUtils(), UNISWAP_UTILS);
        assertEq(UniV3Farm(farmProxy).nfpmUtils(), NONFUNGIBLE_POSITION_MANAGER_UTILS);
    }
}

abstract contract OnERC721ReceivedTest is UniV3FarmTest {
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
                fee: FEE_TIER,
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

        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.IncorrectPoolToken.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId, abi.encode(true));
    }

    function test_OnERC721Received_RevertWhen_IncorrectTickRange() public useKnownActor(user) {
        uint256 tokenId1 = _mintHelper(DAI, USDCe, TICK_LOWER + 1, TICK_UPPER);

        uint256 tokenId2 = _mintHelper(DAI, USDCe, TICK_LOWER + 1, TICK_UPPER + 1);

        uint256 tokenId3 = _mintHelper(DAI, USDCe, TICK_LOWER, TICK_UPPER - 1);

        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId1, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId2, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId3, abi.encode(true));
    }
}

abstract contract ClaimUniswapFeeTest is UniV3FarmTest {
    function test_ClaimPoolFee_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        IFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsClosed.selector));
        UniV3Farm(lockupFarm).claimPoolFee(0);
    }

    function test_ClaimPoolFee_RevertWhen_DepositDoesNotExist_during_claimPoolFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        UniV3Farm(lockupFarm).claimPoolFee(0);
    }

    function test_ClaimPoolFee_RevertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(ClaimableFee.NoFeeToClaim.selector));
        UniV3Farm(lockupFarm).claimPoolFee(depositId);
    }

    function test_claimPoolFee() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = UniV3Farm(lockupFarm).depositToTokenId(depositId);

        (uint256 amt0, uint256 amt1) = IUniswapV3Utils(UNISWAP_UTILS).fees(NFPM, _tokenId);

        vm.expectEmit(address(lockupFarm));
        emit ClaimableFee.PoolFeeCollected(currentActor, _tokenId, amt0, amt1);

        uint256 amt0Before = IERC20(DAI).balanceOf(currentActor);
        uint256 amt1Before = IERC20(USDCe).balanceOf(currentActor);

        UniV3Farm(lockupFarm).claimPoolFee(depositId);

        assertEq(amt0Before + amt0, IERC20(DAI).balanceOf(currentActor));
        assertEq(amt1Before + amt1, IERC20(USDCe).balanceOf(currentActor));
    }
}

abstract contract IncreaseDepositTest is UniV3FarmTest {
    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function test_IncreaseDeposit_RevertWhen_FarmIsInactive() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        UniV3Farm(lockupFarm).farmPauseSwitch(true);

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
        UniV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        UniV3Farm(lockupFarm).increaseDeposit(depositId, [DEPOSIT_AMOUNT, DEPOSIT_AMOUNT], [uint256(0), uint256(0)]);
    }

    function test_IncreaseDeposit_RevertWhen_InvalidAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(UniV3Farm.InvalidAmount.selector));
        UniV3Farm(lockupFarm).increaseDeposit(depositId, [uint256(0), uint256(0)], [uint256(0), uint256(0)]);
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

        UniV3Farm(lockupFarm).initiateCooldown(depositId);
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositIsInCooldown.selector));
        UniV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function testFuzz_IncreaseDeposit(bool lockup, uint256 _depositAmount) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, lockup);

        _depositAmount = bound(_depositAmount, 1, 1e7);
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = UniV3Farm(farm).depositToTokenId(depositId);
        uint256 depositAmount0 = _depositAmount * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount1 = _depositAmount * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [depositAmount0, depositAmount1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, currentActor, depositAmount0);
        deal(USDCe, currentActor, depositAmount1);
        IERC20(DAI).approve(farm, depositAmount0);
        IERC20(USDCe).approve(farm, depositAmount1);

        uint256 oldLiquidity = UniV3Farm(farm).getDepositInfo(depositId).liquidity;
        uint256[2] memory oldTotalFundLiquidity = [
            UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            lockup ? UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity : 0
        ];

        // TODO wanted to check for transfer events but solidity does not support two definitions for the same event
        vm.expectEmit(DAI);
        emit Approval(farm, NFPM, depositAmount0);
        vm.expectEmit(USDCe);
        emit Approval(farm, NFPM, depositAmount1);
        vm.expectEmit(true, false, false, false, NFPM);
        emit IncreaseLiquidity(tokenId, 0, 0, 0);
        vm.expectEmit(true, false, false, false, farm);
        emit OperableDeposit.DepositIncreased(depositId, 0);

        vm.recordLogs();
        UniV3Farm(farm).increaseDeposit(depositId, amounts, minAmounts);
        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        uint128 loggedLiquidity;
        uint256 loggedAmount0;
        uint256 loggedAmount1;
        bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("IncreaseLiquidity(uint256,uint128,uint256,uint256)")) {
                (loggedLiquidity, loggedAmount0, loggedAmount1) =
                    abi.decode(entries[i].data, (uint128, uint256, uint256));
            }
            if (entries[i].topics[0] == keccak256("DepositIncreased(uint256,uint256)")) {
                assertEq(
                    abi.decode(entries[i].data, (uint256)),
                    loggedLiquidity,
                    "DepositIncreased event should have the same liquidity as IncreaseLiquidity event"
                );
                found = true;
            }
        }
        assertTrue(found, "DepositIncreased event not found");
        assertEq(IERC20(DAI).balanceOf(currentActor), depositAmount0 - loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), depositAmount1 - loggedAmount1);
        assertEq(UniV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity + loggedLiquidity);
        assertEq(
            UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldTotalFundLiquidity[0] + loggedLiquidity
        );
        lockup
            ? assertEq(
                UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity,
                oldTotalFundLiquidity[0] + loggedLiquidity
            )
            : assert(true);
    }
}

abstract contract DecreaseDepositTest is UniV3FarmTest {
    uint128 constant dummyLiquidityToWithdraw = 1;

    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function test_DecreaseDeposit_RevertWhen_FarmIsClosed() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        UniV3Farm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IFarm.FarmIsClosed.selector));
        UniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        UniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_CannotWithdrawZeroAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(IFarm.CannotWithdrawZeroAmount.selector));
        UniV3Farm(lockupFarm).decreaseDeposit(depositId, 0, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        UniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    // Decrease deposit test is always for non-lockup deposit.
    function testFuzz_DecreaseDeposit(bool isLockupFarm, uint256 _liquidityToWithdraw) public {
        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);
        skip(1);

        uint128 oldLiquidity = SafeCast.toUint128(UniV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = SafeCast.toUint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = UniV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        UniV3Farm(farm).claimRewards(depositId);
        IERC20(DAI).transfer(makeAddr("Random"), IERC20(DAI).balanceOf(currentActor));
        IERC20(USDCe).transfer(makeAddr("Random"), IERC20(USDCe).balanceOf(currentActor));
        assertEq(IERC20(DAI).balanceOf(currentActor), 0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), 0);

        vm.expectEmit(farm);
        emit OperableDeposit.DepositDecreased(depositId, liquidityToWithdraw);
        vm.expectEmit(true, false, false, false, NFPM);
        emit DecreaseLiquidity(tokenId, 0, 0, 0);
        vm.recordLogs();
        UniV3Farm(farm).decreaseDeposit(depositId, liquidityToWithdraw, minAmounts);
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
        assertEq(UniV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            UniV3Farm(farm).getRewardFundInfo(UniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
    }
}

abstract contract UniV3FarmInheritTest is
    InitializeTest,
    OnERC721ReceivedTest,
    ClaimUniswapFeeTest,
    IncreaseDepositTest,
    DecreaseDepositTest
{}
