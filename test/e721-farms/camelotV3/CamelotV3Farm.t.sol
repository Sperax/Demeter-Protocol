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

contract CamelotV3FarmTest is E721FarmInheritTest {
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
        emit log_named_address("farm", farm);
        (uint256 tokenId, uint256 liquidity) = _mintPosition(baseAmt, user);
        emit log_named_uint("tokenId", tokenId);
        vm.startPrank(user);
        IERC721(NFPM).safeTransferFrom(currentActor, farm, tokenId, abi.encode(locked));
        emit log_named_uint("check", 1);
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
