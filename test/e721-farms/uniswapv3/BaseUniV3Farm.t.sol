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
    INFPM
} from "../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {
    INonfungiblePositionManagerUtils as INFPMUtils,
    Position
} from "../../../../contracts/e721-farms/uniswapv3/interfaces/INonfungiblePositionManagerUtils.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import {BaseE721FarmTest, NFTDepositTest, WithdrawAdditionalTest} from "../BaseE721Farm.t.sol";
import "../../features/BaseFarmWithExpiry.t.sol";

abstract contract BaseUniV3FarmTest is BaseE721FarmTest {
    uint8 public FEE_TIER = 100;
    int24 public TICK_LOWER = -887270;
    int24 public TICK_UPPER = 887270;
    address public NFPM;
    address public UNIV3_FACTORY;
    address public SWAP_ROUTER;
    string public FARM_ID;

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidUniswapPoolConfig();
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
}

abstract contract InitializeTest is BaseUniV3FarmTest {
    function test_RevertWhen_InvalidTickRange() public {
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

    function test_RevertWhen_InvalidUniswapPoolConfig() public {
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
    function test_RevertWhen_IncorrectPoolToken() public useKnownActor(user) {
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

    function test_RevertWhen_IncorrectTickRange() public useKnownActor(user) {
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
    function test_RevertWhen_FarmIsClosed() public useKnownActor(owner) {
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_RevertWhen_DepositDoesNotExist_during_claimUniswapFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_RevertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.NoFeeToClaim.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(1);
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
