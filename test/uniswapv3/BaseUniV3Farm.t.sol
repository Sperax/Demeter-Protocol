// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../contracts/uniswapV3/BaseUniV3Farm.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import tests
import "../BaseFarm.t.sol";

abstract contract BaseUniV3FarmTest is BaseFarmTest {
    uint8 public FEE_TIER = 100;
    int24 public TICK_LOWER = -887270;
    int24 public TICK_UPPER = 887270;
    address public NFPM;
    address public UNIV3_FACTORY;
    address public SWAP_ROUTER;

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

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
}

abstract contract InitializeTest is BaseUniV3FarmTest {
    function test_revertWhen_InvalidTickRange() public {
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        int24 spacing = IUniswapV3TickSpacing(uniswapPool).tickSpacing();

        // Fails for _tickLower >= _tickUpper
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_LOWER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        // Fails for _tickLower < -887272
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887273,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        if (spacing > 1) {
            // Fails for _tickLower % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
            BaseUniV3Farm(farmProxy).initialize({
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _uniswapPoolData: UniswapPoolData({
                    tokenA: USDCe,
                    tokenB: USDT,
                    feeTier: FEE_TIER,
                    tickLowerAllowed: -887271,
                    tickUpperAllowed: TICK_UPPER
                }),
                _rwdTokenData: generateRewardTokenData(),
                _uniswapUtils: UNISWAP_UTILS,
                _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
            });

            // Fails for _tickUpper % spacing != 0
            vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
            BaseUniV3Farm(farmProxy).initialize({
                _farmStartTime: block.timestamp,
                _cooldownPeriod: 0,
                _uniswapPoolData: UniswapPoolData({
                    tokenA: DAI,
                    tokenB: USDCe,
                    feeTier: FEE_TIER,
                    tickLowerAllowed: TICK_LOWER,
                    tickUpperAllowed: 887271
                }),
                _rwdTokenData: generateRewardTokenData(),
                _uniswapUtils: UNISWAP_UTILS,
                _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
            });
        }

        // Fails for _tickUpper > 887272
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidTickRange.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_revertWhen_InvalidUniswapPoolConfig() public {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887273,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: -887271,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887272 + 1
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.InvalidUniswapPoolConfig.selector));
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: 0,
            _uniswapPoolData: UniswapPoolData({
                tokenA: USDCe, // this leads to invalid pool
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: 887271
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });
    }

    function test_initialize() public {
        address uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(DAI, USDCe, FEE_TIER);
        BaseUniV3Farm(farmProxy).initialize({
            _farmStartTime: block.timestamp,
            _cooldownPeriod: COOLDOWN_PERIOD,
            _uniswapPoolData: UniswapPoolData({
                tokenA: DAI,
                tokenB: USDCe,
                feeTier: FEE_TIER,
                tickLowerAllowed: TICK_LOWER,
                tickUpperAllowed: TICK_UPPER
            }),
            _rwdTokenData: generateRewardTokenData(),
            _uniswapUtils: UNISWAP_UTILS,
            _nfpmUtils: NONFUNGIBLE_POSITION_MANAGER_UTILS
        });

        assertEq(BaseUniV3Farm(farmProxy).tickLowerAllowed(), TICK_LOWER);
        assertEq(BaseUniV3Farm(farmProxy).tickUpperAllowed(), TICK_UPPER);
        assertEq(BaseUniV3Farm(farmProxy).uniswapPool(), uniswapPool);
        assertEq(BaseUniV3Farm(farmProxy).owner(), address(this)); // changes to admin when called via deployer
        assertEq(BaseUniV3Farm(farmProxy).lastFundUpdateTime(), block.timestamp);
        assertEq(BaseUniV3Farm(farmProxy).cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(BaseUniV3Farm(farmProxy).uniswapUtils(), UNISWAP_UTILS);
        assertEq(BaseUniV3Farm(farmProxy).nfpmUtils(), NONFUNGIBLE_POSITION_MANAGER_UTILS);
    }
}

abstract contract OnERC721ReceivedTest is BaseUniV3FarmTest {
    function test_revertWhen_NotAUniV3NFT() public {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.NotAUniV3NFT.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_revertWhen_NoData() public useKnownActor(NFPM) {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.NoData.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_revertWhen_IncorrectPoolToken() public useKnownActor(user) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDT).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount1);

        deal(USDT, currentActor, depositAmount2);
        IERC20(USDT).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount2);

        (uint256 tokenId,,,) = INFPM(BaseUniV3Farm(lockupFarm).NFPM()).mint(
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
        changePrank(NFPM);
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), currentActor, tokenId, abi.encode(true));
    }

    function test_revertWhen_IncorrectTickRange() public useKnownActor(user) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1 * 2);
        IERC20(DAI).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount1 * 2);

        deal(USDCe, currentActor, depositAmount2 * 2);
        IERC20(USDCe).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount2 * 2);

        (uint256 tokenId1,,,) = INFPM(BaseUniV3Farm(lockupFarm).NFPM()).mint(
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
        (uint256 tokenId2,,,) = INFPM(BaseUniV3Farm(lockupFarm).NFPM()).mint(
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

        changePrank(NFPM);
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.IncorrectTickRange.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), currentActor, tokenId1, abi.encode(true));

        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.IncorrectTickRange.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), currentActor, tokenId2, abi.encode(true));
    }

    function test_onERC721Received() public useKnownActor(user) {
        uint256 depositAmount1 = 1e3 * 10 ** ERC20(DAI).decimals();
        uint256 depositAmount2 = 1e3 * 10 ** ERC20(USDCe).decimals();

        deal(DAI, currentActor, depositAmount1);
        IERC20(DAI).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount1);

        deal(USDCe, currentActor, depositAmount2);
        IERC20(USDCe).approve(BaseUniV3Farm(lockupFarm).NFPM(), depositAmount2);

        (uint256 tokenId,,,) = INFPM(BaseUniV3Farm(lockupFarm).NFPM()).mint(
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

        changePrank(NFPM);
        assertEq(
            BaseUniV3Farm(lockupFarm).onERC721Received(address(0), currentActor, tokenId, abi.encode(true)),
            bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
        );
    }
}

abstract contract WithdrawAdditionalTest is BaseUniV3FarmTest {
    function test_revertWhen_DepositDoesNotExist_during_withdraw() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).withdraw(0);
    }

    function test_Withdraw() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 0;
        (,, uint256 tokenId,,,) = BaseUniV3Farm(lockupFarm).deposits(depositId);
        BaseFarm(lockupFarm).initiateCooldown(depositId);
        skip((COOLDOWN_PERIOD * 86400) + 100); //100 seconds after the end of CoolDown Period

        vm.expectEmit(true, true, true, true);
        emit Transfer(lockupFarm, currentActor, tokenId);

        BaseUniV3Farm(lockupFarm).withdraw(depositId);
    }
}

abstract contract ClaimUniswapFeeTest is BaseUniV3FarmTest {
    function test_revertWhen_FarmIsClosed() public useKnownActor(owner) {
        BaseFarm(lockupFarm).closeFarm();
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_revertWhen_DepositDoesNotExist_during_claimUniswapFee() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_revertWhen_NoFeeToClaim() public depositSetup(lockupFarm, true) useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(BaseUniV3Farm.NoFeeToClaim.selector));
        BaseUniV3Farm(lockupFarm).claimUniswapFee(0);
    }

    function test_claimUniswapFee() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 0;
        _simulateSwap();
        (,, uint256 tokenId,,,) = BaseUniV3Farm(lockupFarm).deposits(depositId);
        (uint256 amount0, uint256 amount1) = BaseUniV3Farm(lockupFarm).computeUniswapFee(tokenId);

        vm.expectEmit(true, false, false, true);
        emit PoolFeeCollected(currentActor, tokenId, amount0, amount1);

        BaseUniV3Farm(lockupFarm).claimUniswapFee(depositId);
    }
}

abstract contract MiscellaneousTest is BaseUniV3FarmTest {
    function test_NFPM() public {
        address nfpm = BaseUniV3Farm(farmProxy).NFPM();
        assertEq(nfpm, NFPM);
    }

    function test_UNIV3_FACTORY() public {
        address univ3Factory = BaseUniV3Farm(farmProxy).UNIV3_FACTORY();
        assertEq(univ3Factory, UNIV3_FACTORY);
    }
}
