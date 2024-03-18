// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
    E721Farm,
    CamelotV3Farm,
    CamelotPoolData,
    ICamelotV3Factory,
    ICamelotV3TickSpacing,
    INFPM,
    OperableDeposit
} from "../../../contracts/e721-farms/camelotV3/CamelotV3Farm.sol";
import {
    INFPMUtils,
    Position
} from "../../../contracts/e721-farms/camelotV3/interfaces/ICamelotV3NonfungiblePositionManagerUtils.sol";
import "@cryptoalgebra/v1.9-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import {E721FarmTest, E721FarmInheritTest} from "../E721Farm.t.sol";
import {CamelotV3FarmDeployer} from "../../../contracts/e721-farms/camelotV3/CamelotV3FarmDeployer.sol";
import "../../features/ExpirableFarm.t.sol";
import "../../utils/UpgradeUtil.t.sol";

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

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidCamelotPoolConfig();
    error NoData();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();

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
        FarmRegistry registry = FarmRegistry(FARM_REGISTRY);
        camelotV3FarmDeployer = new CamelotV3FarmDeployer(
            FARM_REGISTRY, FARM_ID, CAMELOT_V3_FACTORY, NFPM, CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
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
        Position memory positions = INFPMUtils(CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS).positions(nfpm(), tokenId);
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
        address camelotPool = ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe);
        int24 spacing = ICamelotV3TickSpacing(camelotPool).tickSpacing();

        // Fails for _tickLower >= _tickUpper
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_LOWER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        // Fails for _tickLower < -887272
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: -887272 - 1,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        if (spacing > 1) {
            // Fails for _tickLower % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
            CamelotV3Farm(farmProxy).initialize({
                _farmId: FARM_ID,
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _farmRegistry: FARM_REGISTRY,
                _camelotPoolData: CamelotPoolData({
                    tokenA: DAI,
                    tokenB: USDCe,
                    tickLowerAllowed: -887271,
                    tickUpperAllowed: TICK_UPPER
                }),
                _rwdTokenData: generateRewardTokenData(),
                _camelotV3Factory: CAMELOT_V3_FACTORY,
                _nftContract: NFPM,
                _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
            });

            // Fails for _tickUpper % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
            CamelotV3Farm(farmProxy).initialize({
                _farmId: FARM_ID,
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _farmRegistry: FARM_REGISTRY,
                _camelotPoolData: CamelotPoolData({
                    tokenA: DAI,
                    tokenB: USDCe,
                    tickLowerAllowed: TICK_LOWER,
                    tickUpperAllowed: 887271
                }),
                _rwdTokenData: generateRewardTokenData(),
                _camelotV3Factory: CAMELOT_V3_FACTORY,
                _nftContract: NFPM,
                _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
            });
        }

        // Fails for _tickUpper > 887272
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidTickRange.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_Initialize_RevertWhen_InvalidCamelotPoolConfig() public {
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: -887273,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: -887271,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.InvalidCamelotPoolConfig.selector));
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887271
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_initialize() public {
        address camelotPool = ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe);
        CamelotV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: COOLDOWN_PERIOD_DAYS,
            _farmRegistry: FARM_REGISTRY,
            _camelotPoolData: CamelotPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _camelotV3Factory: CAMELOT_V3_FACTORY,
            _nftContract: NFPM,
            _nfpmUtils: CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        assertEq(CamelotV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(CamelotV3Farm(farmProxy).tickLowerAllowed(), TICK_LOWER);
        assertEq(CamelotV3Farm(farmProxy).tickUpperAllowed(), TICK_UPPER);
        assertEq(CamelotV3Farm(farmProxy).camelotPool(), camelotPool);
        assertEq(CamelotV3Farm(farmProxy).owner(), address(this)); // changes to admin when called via deployer
        assertEq(CamelotV3Farm(farmProxy).lastFundUpdateTime(), block.timestamp);
        assertEq(CamelotV3Farm(farmProxy).cooldownPeriod(), COOLDOWN_PERIOD_DAYS * 1 days);
        assertEq(CamelotV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(CamelotV3Farm(farmProxy).camelotV3Factory(), CAMELOT_V3_FACTORY);
        assertEq(CamelotV3Farm(farmProxy).nftContract(), NFPM);
        assertEq(CamelotV3Farm(farmProxy).nfpmUtils(), CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS);
    }
}

abstract contract OnERC721ReceivedTest is CamelotV3FarmTest {
    function test_OnERC721Received_RevertWhen_IncorrectPoolToken() public useKnownActor(user) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDT).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(NFPM, depositAmount1);

        deal(USDT, currentActor, depositAmount2);
        IERC20(USDT).approve(NFPM, depositAmount2);

        (uint256 tokenId,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDT, // incorrect token
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

        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.IncorrectPoolToken.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId, abi.encode(true));
    }

    function test_OnERC721Received_RevertWhen_IncorrectTickRange() public useKnownActor(user) {
        // Note -> tickspacing of a pool can be changed by the factory owner.
        // If they change a pool’s tickspacing, users’ might not be able to mint new positions adhering to our tickLower and tickUpper in our farm. (see pool’s mint code to understand).

        int24 spacing =
            ICamelotV3TickSpacing(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).tickSpacing();

        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1 * 3);
        IERC20(DAI).approve(NFPM, depositAmount1 * 3);

        deal(USDCe, currentActor, depositAmount2 * 3);
        IERC20(USDCe).approve(NFPM, depositAmount2 * 3);

        (uint256 tokenId1,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                tickLower: TICK_LOWER + spacing,
                tickUpper: TICK_UPPER,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );
        (uint256 tokenId2,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER - spacing,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );

        (uint256 tokenId3,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                tickLower: TICK_LOWER + spacing,
                tickUpper: TICK_UPPER - spacing,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );

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
        Farm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(0);
    }

    function test_ClaimCamelotFee_RevertWhen_DepositDoesNotExist_during_claimCamelotFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(0);
    }

    function test_ClaimCamelotFee_RevertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(CamelotV3Farm.NoFeeToClaim.selector));
        CamelotV3Farm(lockupFarm).claimCamelotFee(depositId);
    }

    // TODO -> Need to check how to test the received accrued fee amounts.
    function test_claimCamelotFee() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = CamelotV3Farm(lockupFarm).depositToTokenId(depositId);

        // amount0, amount1 (accrued fees)

        vm.expectEmit(true, false, false, false, address(lockupFarm)); // for now ignoring amount0 and amount1
        emit PoolFeeCollected(currentActor, _tokenId, 0, 0);

        CamelotV3Farm(lockupFarm).claimCamelotFee(depositId);
    }

    function testFuzz_claimCamelotFee_tickSpacingChanged(int24 tickSpacing)
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.assume(tickSpacing >= 1 && tickSpacing <= 500);
        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = CamelotV3Farm(lockupFarm).depositToTokenId(depositId);

        address camelotFactoryOwner = ICamelotV3FactoryTesting(CAMELOT_V3_FACTORY).owner();
        vm.startPrank(camelotFactoryOwner);
        ICamelotV3PoolTesting(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).setTickSpacing(tickSpacing);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(true, false, false, false, address(lockupFarm)); // for now ignoring amount0 and amount1
        emit PoolFeeCollected(currentActor, _tokenId, 0, 0);

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
    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);

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

        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsInactive.selector));
        CamelotV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
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
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositIsInCooldown.selector));
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
        emit DepositIncreased(depositId, 0);

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

    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    function test_DecreaseDeposit_RevertWhen_FarmIsClosed() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        CamelotV3Farm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_CannotWithdrawZeroAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(Farm.CannotWithdrawZeroAmount.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, 0, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        CamelotV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    // Decrease deposit test is always for non-lockup deposit.
    function testFuzz_DecreaseDeposit(bool isLockupFarm, uint256 _liquidityToWithdraw) public {
        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);

        uint128 oldLiquidity = uint128(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = uint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = CamelotV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        uint256 oldUserToken0Balance = IERC20(DAI).balanceOf(currentActor);
        uint256 oldUserToken1Balance = IERC20(USDCe).balanceOf(currentActor);

        vm.expectEmit(farm);
        emit DepositDecreased(depositId, liquidityToWithdraw);
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
        assertEq(IERC20(DAI).balanceOf(currentActor), oldUserToken0Balance + loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), oldUserToken1Balance + loggedAmount1);
        assertEq(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
    }

    function testFuzz_DecreaseDeposit_tickSpacingChanged(
        bool isLockupFarm,
        uint256 _liquidityToWithdraw,
        int24 tickSpacing
    ) public {
        vm.assume(tickSpacing >= 1 && tickSpacing <= 500);
        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);

        uint128 oldLiquidity = uint128(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = uint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = CamelotV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        uint256 oldUserToken0Balance = IERC20(DAI).balanceOf(currentActor);
        uint256 oldUserToken1Balance = IERC20(USDCe).balanceOf(currentActor);
        vm.stopPrank();

        address camelotFactoryOwner = ICamelotV3FactoryTesting(CAMELOT_V3_FACTORY).owner();
        vm.startPrank(camelotFactoryOwner);
        ICamelotV3PoolTesting(ICamelotV3Factory(CAMELOT_V3_FACTORY).poolByPair(DAI, USDCe)).setTickSpacing(tickSpacing);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(farm);
        emit DepositDecreased(depositId, liquidityToWithdraw);
        vm.expectEmit(true, false, false, false, NFPM);
        emit DecreaseLiquidity(tokenId, 0, 0, 0);

        vm.recordLogs();
        CamelotV3Farm(farm).decreaseDeposit(depositId, liquidityToWithdraw, minAmounts);
        VmSafe.Log[] memory entries = vm.getRecordedLogs();

        uint128 loggedLiquidity;
        uint256 loggedAmount0;
        uint256 loggedAmount1;
        // bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DecreaseLiquidity(uint256,uint128,uint256,uint256)")) {
                (loggedLiquidity, loggedAmount0, loggedAmount1) =
                    abi.decode(entries[i].data, (uint128, uint256, uint256));
                // found = true;
            }
        }
        // assertTrue(found, "DecreaseLiquidity event not found");
        assertEq(loggedLiquidity, liquidityToWithdraw);
        assertEq(IERC20(DAI).balanceOf(currentActor), oldUserToken0Balance + loggedAmount0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), oldUserToken1Balance + loggedAmount1);
        assertEq(CamelotV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            CamelotV3Farm(farm).getRewardFundInfo(CamelotV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
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
    E721FarmInheritTest
{
    function setUp() public override(CamelotV3FarmTest, FarmTest) {
        super.setUp();
    }
}