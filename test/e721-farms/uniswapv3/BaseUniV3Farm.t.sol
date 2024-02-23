// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
    BaseE721Farm,
    BaseUniV3Farm,
    UniswapPoolData,
    IUniswapV3Factory,
    IUniswapV3TickSpacing,
    INFPM,
    OperableDeposit
} from "../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {
    INFPMUtils,
    Position
} from "../../../contracts/e721-farms/uniswapV3/interfaces/INonfungiblePositionManagerUtils.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import {BaseE721FarmTest, BaseE721FarmInheritTest} from "../BaseE721Farm.t.sol";
import {Demeter_BaseUniV3FarmDeployer} from "../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3FarmDeployer.sol";
import "../../features/BaseFarmWithExpiry.t.sol";
import "../../utils/UpgradeUtil.t.sol";

import {VmSafe} from "forge-std/Vm.sol";

abstract contract BaseUniV3FarmTest is BaseE721FarmTest {
    uint8 public FEE_TIER = 100;
    int24 public TICK_LOWER = -887270;
    int24 public TICK_UPPER = 887270;
    address public NFPM;
    address public UNIV3_FACTORY;
    address public SWAP_ROUTER;
    string public FARM_ID;

    uint256 constant depositId = 1;
    Demeter_BaseUniV3FarmDeployer public uniV3FarmDeployer;

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

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
        address impl = address(new BaseUniV3Farm());
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        farmProxy = upgradeUtil.deployErc1967Proxy(address(impl));

        // Deploy and register farm deployer
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        uniV3FarmDeployer = new Demeter_BaseUniV3FarmDeployer(
            DEMETER_FACTORY, FARM_ID, UNIV3_FACTORY, NFPM, UNISWAP_UTILS, NONFUNGIBLE_POSITION_MANAGER_UTILS
        );
        factory.registerFarmDeployer(address(uniV3FarmDeployer));

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
        Demeter_BaseUniV3FarmDeployer.FarmData memory _data = Demeter_BaseUniV3FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
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
        BaseE721Farm(farm).onERC721Received(address(0), currentActor, tokenId, abi.encode(locked));
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

abstract contract InitializeTest is BaseUniV3FarmTest {
    function test_Initialize_RevertWhen_InvalidTickRange() public {
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        int24 spacing = IUniswapV3TickSpacing(uniswapPool).tickSpacing();

        // Fails for _tickLower >= _tickUpper
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_LOWER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        // Fails for _tickLower < -887272
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887273,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        if (spacing > 1) {
            // Fails for _tickLower % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
            BaseUniV3Farm(farmProxy).initialize({
                _farmId: FARM_ID,
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _factory: DEMETER_FACTORY,
                _uniswapPoolData: UniswapPoolData({
                    tokenA: USDCe,
                    tokenB: USDT,
                    feeTier: FEE_TIER,
                    tickLowerAllowed: -887271,
                    tickUpperAllowed: TICK_UPPER
                }),
                _rwdTokenData: generateRewardTokenData(),
                _uniV3Factory: UNIV3_FACTORY,
                _nftContract: NFPM,
                _uniswapUtils: UNISWAP_UTILS,
                _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
            });

            // Fails for _tickUpper % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
            BaseUniV3Farm(farmProxy).initialize({
                _farmId: FARM_ID,
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _factory: DEMETER_FACTORY,
                _uniswapPoolData: UniswapPoolData({
                    tokenA: DAI,
                    tokenB: USDCe,
                    feeTier: FEE_TIER,
                    tickLowerAllowed: TICK_LOWER,
                    tickUpperAllowed: 887271
                }),
                _rwdTokenData: generateRewardTokenData(),
                _uniV3Factory: UNIV3_FACTORY,
                _nftContract: NFPM,
                _uniswapUtils: UNISWAP_UTILS,
                _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
            });
        }

        // Fails for _tickUpper > 887272
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_Initialize_RevertWhen_InvalidUniswapPoolConfig() public {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887273,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887271,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887271
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_initialize() public {
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        BaseUniV3Farm(farmProxy).initialize({
            _farmId: FARM_ID,
            _farmStartTime: block.timestamp,
            _cooldownPeriod: COOLDOWN_PERIOD,
            _factory: DEMETER_FACTORY,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniV3Factory: UNIV3_FACTORY,
            _nftContract: NFPM,
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        assertEq(BaseUniV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(BaseUniV3Farm(farmProxy).tickLowerAllowed(), TICK_LOWER);
        assertEq(BaseUniV3Farm(farmProxy).tickUpperAllowed(), TICK_UPPER);
        assertEq(BaseUniV3Farm(farmProxy).uniswapPool(), uniswapPool);
        assertEq(BaseUniV3Farm(farmProxy).owner(), address(this)); // changes to admin when called via deployer
        assertEq(BaseUniV3Farm(farmProxy).lastFundUpdateTime(), block.timestamp);
        assertEq(BaseUniV3Farm(farmProxy).cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(BaseUniV3Farm(farmProxy).farmId(), FARM_ID);
        assertEq(BaseUniV3Farm(farmProxy).uniV3Factory(), UNIV3_FACTORY);
        assertEq(BaseUniV3Farm(farmProxy).nftContract(), NFPM);
        assertEq(BaseUniV3Farm(farmProxy).uniswapUtils(), UNISWAP_UTILS);
        assertEq(BaseUniV3Farm(farmProxy).nfpmUtils(), NONFUNGIBLE_POSITION_MANAGER_UTILS);
    }
}

abstract contract OnERC721ReceivedTest is BaseUniV3FarmTest {
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

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.IncorrectPoolToken.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId, abi.encode(true));
    }

    function test_OnERC721Received_RevertWhen_IncorrectTickRange() public useKnownActor(user) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1 * 2);
        IERC20(DAI).approve(NFPM, depositAmount1 * 2);

        deal(USDCe, currentActor, depositAmount2 * 2);
        IERC20(USDCe).approve(NFPM, depositAmount2 * 2);

        (uint256 tokenId1,,,) = INFPM(NFPM).mint(
            INFPM.MintParams({
                token0: DAI,
                token1: USDCe,
                fee: FEE_TIER,
                tickLower: TICK_LOWER + 1,
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
                fee: FEE_TIER,
                tickLower: TICK_LOWER + 1,
                tickUpper: TICK_UPPER + 1,
                amount0Desired: depositAmount1,
                amount1Desired: depositAmount2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: currentActor,
                deadline: block.timestamp
            })
        );

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId1, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.IncorrectTickRange.selector));
        IERC721(NFPM).safeTransferFrom(user, lockupFarm, tokenId2, abi.encode(true));
    }
}

abstract contract ClaimUniswapFeeTest is BaseUniV3FarmTest {
    function test_ClaimUniswapFee_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_ClaimUniswapFee_RevertWhen_DepositDoesNotExist_during_claimUniswapFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_ClaimUniswapFee_RevertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.NoFeeToClaim.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(depositId);
    }

    function test_claimUniswapFee() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        _simulateSwap();
        uint256 _tokenId = BaseUniV3Farm(lockupFarm).depositToTokenId(depositId);
        (uint256 amount0, uint256 amount1) = BaseUniV3Farm(lockupFarm).computeUniswapFee(_tokenId);

        vm.expectEmit(address(lockupFarm));
        emit PoolFeeCollected(currentActor, _tokenId, amount0, amount1);

        BaseUniV3Farm(lockupFarm).claimUniswapFee(depositId);
    }
}

abstract contract IncreaseDepositTest is BaseUniV3FarmTest {
    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);

    function test_IncreaseDeposit_RevertWhen_FarmIsInactive() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        BaseUniV3Farm(lockupFarm).farmPauseSwitch(true);

        uint256 deposit0 = DEPOSIT_AMOUNT * 10 ** ERC20(DAI).decimals();
        uint256 deposit1 = DEPOSIT_AMOUNT * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [deposit0, deposit1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, user, deposit0);
        deal(USDCe, user, deposit1);
        vm.startPrank(user);

        IERC20(DAI).approve(lockupFarm, deposit0);
        IERC20(USDCe).approve(lockupFarm, deposit1);

        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsInactive.selector));
        BaseUniV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).increaseDeposit(depositId, [DEPOSIT_AMOUNT, DEPOSIT_AMOUNT], [uint256(0), uint256(0)]);
    }

    function test_IncreaseDeposit_RevertWhen_InvalidAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidAmount.selector));
        BaseUniV3Farm(lockupFarm).increaseDeposit(depositId, [uint256(0), uint256(0)], [uint256(0), uint256(0)]);
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

        BaseUniV3Farm(lockupFarm).initiateCooldown(depositId);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositIsInCooldown.selector));
        BaseUniV3Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function testFuzz_IncreaseDeposit(bool lockup, uint256 _depositAmount) public {
        address farm;
        farm = lockup ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, lockup);

        _depositAmount = bound(_depositAmount, 1, 1e7);
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = BaseUniV3Farm(farm).depositToTokenId(depositId);
        uint256 depositAmount0 = _depositAmount * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount1 = _depositAmount * 10 ** ERC20(USDCe).decimals();
        uint256[2] memory amounts = [depositAmount0, depositAmount1];
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];

        deal(DAI, currentActor, depositAmount0);
        deal(USDCe, currentActor, depositAmount1);
        IERC20(DAI).approve(farm, depositAmount0);
        IERC20(USDCe).approve(farm, depositAmount1);

        uint256 oldLiquidity = BaseUniV3Farm(farm).getDepositInfo(depositId).liquidity;
        uint256[2] memory oldTotalFundLiquidity = [
            BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            lockup ? BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity : 0
        ];

        // TODO wanted to check for transfer events but solidity does not support two definitions for the same event
        vm.expectEmit(DAI);
        emit Approval(farm, NFPM, depositAmount0);
        vm.expectEmit(USDCe);
        emit Approval(farm, NFPM, depositAmount1);
        vm.expectEmit(true, false, false, false, NFPM);
        emit IncreaseLiquidity(tokenId, 0, 0, 0);
        vm.expectEmit(true, false, false, false, farm);
        emit DepositIncreased(depositId, 0);

        vm.recordLogs();
        BaseUniV3Farm(farm).increaseDeposit(depositId, amounts, minAmounts);
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
        assertEq(BaseUniV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity + loggedLiquidity);
        assertEq(
            BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldTotalFundLiquidity[0] + loggedLiquidity
        );
        lockup
            ? assertEq(
                BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).LOCKUP_FUND_ID()).totalLiquidity,
                oldTotalFundLiquidity[0] + loggedLiquidity
            )
            : assert(true);
    }
}

abstract contract DecreaseDepositTest is BaseUniV3FarmTest {
    uint128 constant dummyLiquidityToWithdraw = 1;

    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    function test_DecreaseDeposit_RevertWhen_FarmIsClosed() public depositSetup(lockupFarm, true) {
        vm.startPrank(owner);
        BaseUniV3Farm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseUniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DepositDoesNotExist() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_CannotWithdrawZeroAmount()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        BaseUniV3Farm(lockupFarm).decreaseDeposit(depositId, 0, [uint256(0), uint256(0)]);
    }

    function test_DecreaseDeposit_RevertWhen_DecreaseDepositNotPermitted()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        BaseUniV3Farm(lockupFarm).decreaseDeposit(depositId, dummyLiquidityToWithdraw, [uint256(0), uint256(0)]);
    }

    // Decrease deposit test is always for non-lockup deposit.
    function testFuzz_DecreaseDeposit(bool isLockupFarm, uint256 _liquidityToWithdraw) public {
        address farm;
        farm = isLockupFarm ? lockupFarm : nonLockupFarm;
        depositSetupFn(farm, false);

        uint128 oldLiquidity = uint128(BaseUniV3Farm(farm).getDepositInfo(depositId).liquidity);
        uint128 liquidityToWithdraw = uint128(bound(_liquidityToWithdraw, 1, oldLiquidity));
        assertEq(currentActor, user);
        assert(DAI < USDCe); // To ensure that the first token is DAI and the second is USDCe

        vm.startPrank(user);
        uint256 tokenId = BaseUniV3Farm(farm).depositToTokenId(depositId);
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        uint256 oldCommonTotalLiquidity =
            BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity;
        uint256 oldUserToken0Balance = IERC20(DAI).balanceOf(currentActor);
        uint256 oldUserToken1Balance = IERC20(USDCe).balanceOf(currentActor);

        vm.expectEmit(farm);
        emit DepositDecreased(depositId, liquidityToWithdraw);
        vm.expectEmit(true, false, false, false, NFPM);
        emit DecreaseLiquidity(tokenId, 0, 0, 0);

        vm.recordLogs();
        BaseUniV3Farm(farm).decreaseDeposit(depositId, liquidityToWithdraw, minAmounts);
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
        assertEq(BaseUniV3Farm(farm).getDepositInfo(depositId).liquidity, oldLiquidity - liquidityToWithdraw);
        assertEq(
            BaseUniV3Farm(farm).getRewardFundInfo(BaseUniV3Farm(farm).COMMON_FUND_ID()).totalLiquidity,
            oldCommonTotalLiquidity - liquidityToWithdraw
        );
    }
}

abstract contract BaseUniV3FarmInheritTest is
    InitializeTest,
    OnERC721ReceivedTest,
    ClaimUniswapFeeTest,
    IncreaseDepositTest,
    DecreaseDepositTest
{}
