// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../Farm.t.sol";
import "../../features/ExpirableFarm.t.sol";
import {
    INFTPoolFactory,
    IPositionHelper,
    INFTPool
} from "../../../contracts/e721-farms/camelotV2/interfaces/ICamelotV2.sol";
import "../../../contracts/e721-farms/camelotV2/CamelotV2FarmDeployer.sol";
import "../../../contracts/e721-farms/camelotV2/CamelotV2Farm.sol";
import "../E721Farm.t.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UpgradeUtil} from "../../utils/UpgradeUtil.t.sol";
import {OperableDeposit} from "../../../contracts/features/OperableDeposit.sol";
import {FarmRegistry} from "../../../contracts/FarmRegistry.sol";
import {Deposit, Subscription, RewardFund} from "../../../contracts/interfaces/DataTypes.sol";
import {E721Farm} from "../../../contracts/e721-farms/E721Farm.sol";

abstract contract CamelotV2FarmTest is E721FarmTest {
    using SafeERC20 for IERC20;

    string public FARM_ID = "Demeter_CamelotV2_v1";

    UpgradeUtil internal upgradeUtil;
    CamelotV2Farm public farmImpl;

    CamelotV2FarmDeployer internal camelotV2FarmDeployer;

    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(PROXY_OWNER);
        FarmRegistry registry = FarmRegistry(FARM_REGISTRY);
        camelotV2FarmDeployer =
            new CamelotV2FarmDeployer(FARM_REGISTRY, FARM_ID, CAMELOT_FACTORY, ROUTER, NFT_POOL_FACTORY);
        registry.registerFarmDeployer(address(camelotV2FarmDeployer));
        vm.stopPrank();

        // Configure rewardTokens
        rwdTokens.push(DAI);
        rwdTokens.push(USDCe);

        invalidRewardToken = USDT;

        // Create and setup Farms
        lockupFarm = createFarm(block.timestamp, true);
        nonLockupFarm = createFarm(block.timestamp, false);
    }

    function createFarm(uint256 startTime, bool lockup) public override useKnownActor(owner) returns (address) {
        address[] memory rewardToken = rwdTokens;
        RewardTokenData[] memory rwdTokenData = new RewardTokenData[](rewardToken.length);
        for (uint8 i = 0; i < rewardToken.length; ++i) {
            rwdTokenData[i] = RewardTokenData(rewardToken[i], currentActor);
        }
        CamelotV2FarmDeployer.CamelotPoolData memory _poolData =
            CamelotV2FarmDeployer.CamelotPoolData({tokenA: DAI, tokenB: USDCe});
        /// Create Farm
        CamelotV2FarmDeployer.FarmData memory _data = CamelotV2FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD_DAYS : 0,
            camelotPoolData: _poolData,
            rewardData: rwdTokenData
        });
        IERC20(FEE_TOKEN()).approve(address(camelotV2FarmDeployer), 1e20);
        address farm = camelotV2FarmDeployer.createFarm(_data);

        assertEq(CamelotV2Farm(farm).farmId(), FARM_ID);
        return farm;
    }

    function deposit(address farm, bool locked, uint256 amt) public override useKnownActor(user) returns (uint256) {
        bytes memory lockup = locked ? abi.encode(true) : abi.encode(false);
        uint256 amt1 = amt * 10 ** ERC20(DAI).decimals();
        deal(DAI, user, amt1);
        uint256 amt2 = amt * 10 ** ERC20(USDCe).decimals();
        deal(USDCe, user, amt2);
        IERC20(DAI).forceApprove(POSITION_HELPER, amt1);
        IERC20(USDCe).forceApprove(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            DAI, USDCe, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(nfpm()), 0
        );
        uint256 tokenId = INFTPool(nfpm()).lastTokenId();
        IERC721(nfpm()).safeTransferFrom(user, farm, tokenId, lockup);
        (uint256 liquidity,,,,,,,) = INFTPool(nfpm()).getStakingPosition(tokenId);
        return liquidity;
    }

    function deposit(address farm, bool locked, uint256 amt, bytes memory revertMsg)
        public
        override
        useKnownActor(user)
    {
        bytes memory lockup = locked ? abi.encode(true) : abi.encode(false);
        uint256 tokenId = INFTPool(nfpm()).lastTokenId() + 1;
        address poolAddress = INFTPoolFactory(NFT_POOL_FACTORY).getPool(LP_TOKEN);
        if (keccak256(abi.encodePacked(revertMsg)) == keccak256(abi.encodePacked(Farm.NoLiquidityInPosition.selector)))
        {
            amt = 100;
        }
        uint256 amt1 = amt * 10 ** ERC20(DAI).decimals();
        deal(DAI, user, amt1);
        uint256 amt2 = amt * 10 ** ERC20(USDCe).decimals();
        deal(USDCe, user, amt2);
        IERC20(DAI).forceApprove(POSITION_HELPER, amt1);
        IERC20(USDCe).forceApprove(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            DAI, USDCe, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(nfpm()), 0
        );
        if (keccak256(abi.encodePacked(revertMsg)) == keccak256(abi.encodePacked(Farm.NoLiquidityInPosition.selector)))
        {
            vm.mockCall(
                poolAddress,
                abi.encodeWithSelector(INFTPool.getStakingPosition.selector, tokenId),
                abi.encode(0, 0, 0, 0, 0, 0, 0, 0)
            );
        }
        vm.expectRevert(revertMsg);
        IERC721(poolAddress).safeTransferFrom(user, farm, tokenId, lockup);
        if (keccak256(abi.encodePacked(revertMsg)) == keccak256(abi.encodePacked(Farm.NoLiquidityInPosition.selector)))
        {
            vm.clearMockedCalls();
        }
    }

    function createPosition(address from) public override returns (uint256 tokenId, address nftContract) {
        tokenId = INFTPool(nfpm()).lastTokenId() + 1;
        uint256 amt = 100;
        uint256 amt1 = amt * 10 ** ERC20(DAI).decimals();
        deal(DAI, from, amt1);
        uint256 amt2 = amt * 10 ** ERC20(USDCe).decimals();
        deal(USDCe, from, amt2);
        IERC20(DAI).forceApprove(POSITION_HELPER, amt1);
        IERC20(USDCe).forceApprove(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            DAI, USDCe, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, from, INFTPool(nfpm()), 0
        );
        nftContract = nfpm();
    }

    function getLiquidity(uint256 tokenId) public view override returns (uint256 liquidity) {
        (liquidity,,,,,,,) = INFTPool(nfpm()).getStakingPosition(tokenId);
    }

    function nfpm() internal view override returns (address poolAddress) {
        poolAddress = INFTPoolFactory(NFT_POOL_FACTORY).getPool(LP_TOKEN);
    }

    function createFarmImplementation() public useKnownActor(owner) returns (address) {
        address camelotProxy;
        farmImpl = new CamelotV2Farm();
        upgradeUtil = new UpgradeUtil();
        camelotProxy = upgradeUtil.deployErc1967Proxy(address(farmImpl));
        return camelotProxy;
    }

    function test_Initialize_RevertWhen_camelotPairIsZero() public {
        address farm = createFarmImplementation();
        address[] memory rewardToken = rwdTokens;
        RewardTokenData[] memory rwdTokenData = new RewardTokenData[](rewardToken.length);
        for (uint8 i = 0; i < rewardToken.length; ++i) {
            rwdTokenData[i] = RewardTokenData(rewardToken[i], currentActor);
        }
        vm.expectRevert(abi.encodeWithSelector(CamelotV2Farm.InvalidCamelotPoolConfig.selector));
        CamelotV2Farm(farm).initialize(
            FARM_ID, block.timestamp, 0, address(registry), address(0), rwdTokenData, ROUTER, NFT_POOL_FACTORY
        );
    }
}

abstract contract OnNFTHarvestTest is CamelotV2FarmTest {
    function test_onNFTHarvest_RevertWhen_NotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(CamelotV2Farm.NotAllowed.selector));
        CamelotV2Farm(lockupFarm).onNFTHarvest(address(0), address(0), 742, 1, 1);
    }

    function test_onNFTHarvest() public {
        address nftPool = CamelotV2Farm(lockupFarm).nftContract();
        vm.startPrank(nftPool);
        bool harvested = CamelotV2Farm(lockupFarm).onNFTHarvest(address(0), user, 742, 1, 1);
        assertEq(harvested, true);
    }
}

abstract contract ClaimPoolRewardsTest is CamelotV2FarmTest {
    function test_claimPoolRewards_RevertWhen_FarmIsClosed()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(7 days);
        vm.startPrank(Farm(nonLockupFarm).owner());
        Farm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        uint256 PoolRewards = CamelotV2Farm(nonLockupFarm).computePoolRewards(0);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        CamelotV2Farm(nonLockupFarm).claimPoolRewards(0);
        assertEq(0, PoolRewards);
    }

    function test_claimPoolRewards_RevertWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        CamelotV2Farm(nonLockupFarm).claimPoolRewards(2);
    }

    function test_claimPoolRewards_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        skip(14 days);

        CamelotV2Farm(nonLockupFarm).claimPoolRewards(1);
    }
}

abstract contract CamelotIncreaseDepositTest is CamelotV2FarmTest {
    using SafeERC20 for IERC20;

    function test_IncreaseDeposit_RevertWhen_FarmIsInactive()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        vm.startPrank(Farm(nonLockupFarm).owner());
        Farm(nonLockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsInactive.selector));
        CamelotV2Farm(nonLockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        uint8 numDeposits = uint8(CamelotV2Farm(nonLockupFarm).totalDeposits());
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        CamelotV2Farm(nonLockupFarm).increaseDeposit(numDeposits + 1, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_InvalidAmount()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 0;
        amounts[1] = 0;
        skip(7 days);

        vm.expectRevert(abi.encodeWithSelector(CamelotV2Farm.InvalidAmount.selector));
        CamelotV2Farm(nonLockupFarm).increaseDeposit(1, amounts, minAmounts);
    }

    function test_IncreaseDeposit_RevertWhen_depositInCoolDown()
        public
        depositSetup(lockupFarm, true)
        useKnownActor(user)
    {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(lockupFarm, 1e22);
        IERC20(USDCe).forceApprove(lockupFarm, 1e22);
        CamelotV2Farm(lockupFarm).initiateCooldown(depositId);
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositIsInCooldown.selector));
        CamelotV2Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
    }

    function test_AmountA_noLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e4 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e23);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        Deposit memory userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        RewardFund memory _rwdFund = CamelotV2Farm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqBefore = _rwdFund.totalLiquidity;

        Subscription memory sub =
            CamelotV2Farm(nonLockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(nonLockupFarm).COMMON_FUND_ID());
        uint256[] memory _rewardDebtBefore = sub.rewardDebt;

        CamelotV2Farm(nonLockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        _rwdFund = CamelotV2Farm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqAfter = _rwdFund.totalLiquidity;

        sub = CamelotV2Farm(nonLockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(nonLockupFarm).COMMON_FUND_ID());
        uint256[] memory _rewardDebtAfter = sub.rewardDebt;
        for (uint8 i; i < _rewardDebtBefore.length; i++) {
            assertTrue(_rewardDebtAfter[i] > _rewardDebtBefore[i]);
        }

        userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        rewardsClaimed = userDeposit.totalRewardsClaimed;

        assertTrue(totalFundLiqAfter > totalFundLiqBefore, "Failed to increase total liquidity");
        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_IncreaseDeposit_noLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        Deposit memory userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        CamelotV2Farm(nonLockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        rewardsClaimed = userDeposit.totalRewardsClaimed;

        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_IncreaseDeposit_lockupFarm() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        uint256[] memory totalFundLiquidity = new uint256[](2);
        uint256 depositId = 1;
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(lockupFarm, 1e22);
        IERC20(USDCe).forceApprove(lockupFarm, 1e22);
        RewardFund memory _rwdFund = CamelotV2Farm(lockupFarm).getRewardFundInfo(0);
        totalFundLiquidity[0] = _rwdFund.totalLiquidity;
        Subscription memory sub =
            CamelotV2Farm(lockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(lockupFarm).COMMON_FUND_ID());
        uint256[] memory _commonRewardDebtBefore = sub.rewardDebt;
        sub = CamelotV2Farm(lockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(lockupFarm).LOCKUP_FUND_ID());
        uint256[] memory _lockupRewardDebtBefore = sub.rewardDebt;
        CamelotV2Farm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        _rwdFund = CamelotV2Farm(lockupFarm).getRewardFundInfo(0);
        totalFundLiquidity[1] = _rwdFund.totalLiquidity;
        sub = CamelotV2Farm(lockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(lockupFarm).COMMON_FUND_ID());
        uint256[] memory _commonRewardDebtAfter = sub.rewardDebt;
        sub = CamelotV2Farm(lockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(lockupFarm).LOCKUP_FUND_ID());
        uint256[] memory _lockupRewardDebtAfter = sub.rewardDebt;
        for (uint8 i; i < _commonRewardDebtBefore.length; i++) {
            assertTrue(_commonRewardDebtAfter[i] > _commonRewardDebtBefore[i]);
            assertTrue(_lockupRewardDebtAfter[i] > _lockupRewardDebtBefore[i]);
        }
        Deposit memory userDepositAfter = CamelotV2Farm(lockupFarm).getDepositInfo(depositId);
        rewardsClaimed = userDepositAfter.totalRewardsClaimed;
        assertTrue(totalFundLiquidity[0] < totalFundLiquidity[1]);
        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }
}

abstract contract CamelotDecreaseDepositTest is CamelotV2FarmTest {
    using SafeERC20 for IERC20;

    function test_DecreaseDeposit_RevertWhen_FarmIsClosed()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256 depositId = 1;
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        Deposit memory userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        vm.startPrank(Farm(nonLockupFarm).owner());
        Farm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(Farm.FarmIsClosed.selector));
        CamelotV2Farm(nonLockupFarm).decreaseDeposit(depositId, liquidity, minAmounts);
    }

    function test_DecreaseDeposit_RevertWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        uint8 numDeposits = uint8(CamelotV2Farm(nonLockupFarm).totalDeposits());
        Deposit memory userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(numDeposits);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(Farm.DepositDoesNotExist.selector));
        CamelotV2Farm(nonLockupFarm).decreaseDeposit(numDeposits + 1, liquidity, minAmounts);
    }

    function test_DecreaseDeposit_RevertWhen_ZeroAmount()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256 depositId = 1;
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(Farm.CannotWithdrawZeroAmount.selector));
        CamelotV2Farm(nonLockupFarm).decreaseDeposit(depositId, 0, minAmounts);
    }

    function test_DecreaseDeposit_lockupFarm() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = CamelotV2Farm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);

        Deposit memory userDeposit = CamelotV2Farm(lockupFarm).getDepositInfo(1);
        uint256 liquidity = userDeposit.liquidity;
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        CamelotV2Farm(lockupFarm).decreaseDeposit(1, liquidity - 1e4, minAmounts);
    }

    function test_DecreaseDeposit_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256 depositId = 1;
        Deposit memory userDeposit = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        uint256 liquidity = userDeposit.liquidity;
        uint256[] memory BalanceBefore = new uint256[](2);

        //skipping 7 days
        skip(7 days);
        CamelotV2Farm(nonLockupFarm).claimRewards(depositId);
        BalanceBefore[0] = IERC20(DAI).balanceOf(user);
        BalanceBefore[1] = IERC20(USDCe).balanceOf(user);
        RewardFund memory _rwdFund = CamelotV2Farm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqBefore = _rwdFund.totalLiquidity;
        Subscription memory sub =
            CamelotV2Farm(nonLockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(nonLockupFarm).COMMON_FUND_ID());
        uint256[] memory _rewardDebtBefore = sub.rewardDebt;
        //We're not checking the data here
        vm.expectEmit(true, false, false, false);
        emit DepositDecreased(1, liquidity / 2);
        CamelotV2Farm(nonLockupFarm).decreaseDeposit(depositId, liquidity / 2, minAmounts);
        Deposit memory userDepositAfter = CamelotV2Farm(nonLockupFarm).getDepositInfo(depositId);
        _rwdFund = CamelotV2Farm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqAfter = _rwdFund.totalLiquidity;
        sub = CamelotV2Farm(nonLockupFarm).getSubscriptionInfo(depositId, CamelotV2Farm(nonLockupFarm).COMMON_FUND_ID());
        uint256[] memory _rewardDebtAfter = sub.rewardDebt;
        for (uint8 i; i < _rewardDebtBefore.length; i++) {
            assertTrue(_rewardDebtAfter[i] < _rewardDebtBefore[i], "Reward debt failure");
        }

        assertTrue(totalFundLiqAfter < totalFundLiqBefore, "Failed to increase total liquidity");

        //Asserting Data
        assertApproxEqAbs(userDepositAfter.liquidity, liquidity / 2, 1);
    }
}

contract DemeterCamelotFarmInheritTest is
    FarmInheritTest,
    E721FarmInheritTest,
    ExpirableFarmInheritTest,
    OnNFTHarvestTest,
    ClaimPoolRewardsTest,
    CamelotIncreaseDepositTest,
    CamelotDecreaseDepositTest
{
    function setUp() public override(CamelotV2FarmTest, FarmTest) {
        super.setUp();
    }
}
