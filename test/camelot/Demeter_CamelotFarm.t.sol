// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseFarm.t.sol";
import "../features/BaseFarmWithExpiry.t.sol";
import {BaseFarmTest} from "../BaseFarm.t.sol";
import {INFTPoolFactory, IPositionHelper, INFTPool} from "../../contracts/camelot/interfaces/ICamelot.sol";
import "../../contracts/camelot/Demeter_CamelotFarm_Deployer.sol";
import "../../contracts/camelot/Demeter_CamelotFarm.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UpgradeUtil} from "../../test/utils/UpgradeUtil.t.sol";
import {OperableDeposit} from "../../contracts/features/OperableDeposit.sol";
import {FarmFactory} from "../../contracts/FarmFactory.sol";
import {Deposit, Subscription, RewardFund} from "../../contracts/interfaces/DataTypes.sol";

contract Demeter_CamelotFarmTest is BaseFarmTest {
    using SafeERC20 for IERC20;

    string public FARM_ID = "Demeter_Camelot_v1";

    UpgradeUtil internal upgradeUtil;
    Demeter_CamelotFarm public farmImpl;

    Demeter_CamelotFarm_Deployer internal demeter_camelotFarm_deployer;

    event DepositIncreased(uint256 indexed depositId, uint256 liquidity);
    event DepositDecreased(uint256 indexed depositId, uint256 liquidity);

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(PROXY_OWNER);
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        demeter_camelotFarm_deployer =
            new Demeter_CamelotFarm_Deployer(DEMETER_FACTORY, FARM_ID, CAMELOT_FACTORY, ROUTER, NFT_POOL_FACTORY);
        factory.registerFarmDeployer(address(demeter_camelotFarm_deployer));
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
        Demeter_CamelotFarm_Deployer.CamelotPoolData memory _poolData =
            Demeter_CamelotFarm_Deployer.CamelotPoolData({tokenA: DAI, tokenB: USDCe});
        /// Create Farm
        Demeter_CamelotFarm_Deployer.FarmData memory _data = Demeter_CamelotFarm_Deployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            camelotPoolData: _poolData,
            rewardData: rwdTokenData
        });
        IERC20(FEE_TOKEN()).approve(address(demeter_camelotFarm_deployer), 1e20);
        address farm = demeter_camelotFarm_deployer.createFarm(_data);

        assertEq(Demeter_CamelotFarm(farm).farmId(), FARM_ID);
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
            DAI, USDCe, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(getPoolAddress()), 0
        );
        uint256 tokenId = INFTPool(getPoolAddress()).lastTokenId();
        IERC721(getPoolAddress()).safeTransferFrom(user, farm, tokenId, lockup);
        (uint256 liquidity,,,,,,,) = INFTPool(getPoolAddress()).getStakingPosition(tokenId);
        return liquidity;
    }

    function deposit(address farm, bool locked, uint256 amt, bytes memory revertMsg)
        public
        override
        useKnownActor(user)
    {
        bytes memory lockup = locked ? abi.encode(true) : abi.encode(false);
        uint256 tokenId = INFTPool(getPoolAddress()).lastTokenId() + 1;
        address poolAddress = INFTPoolFactory(NFT_POOL_FACTORY).getPool(LP_TOKEN);
        if (
            keccak256(abi.encodePacked(revertMsg))
                == keccak256(abi.encodePacked(BaseFarm.NoLiquidityInPosition.selector))
        ) amt = 100;
        uint256 amt1 = amt * 10 ** ERC20(DAI).decimals();
        deal(DAI, user, amt1);
        uint256 amt2 = amt * 10 ** ERC20(USDCe).decimals();
        deal(USDCe, user, amt2);
        IERC20(DAI).forceApprove(POSITION_HELPER, amt1);
        IERC20(USDCe).forceApprove(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            DAI, USDCe, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(getPoolAddress()), 0
        );
        if (
            keccak256(abi.encodePacked(revertMsg))
                == keccak256(abi.encodePacked(BaseFarm.NoLiquidityInPosition.selector))
        ) {
            vm.mockCall(
                poolAddress,
                abi.encodeWithSelector(INFTPool.getStakingPosition.selector, tokenId),
                abi.encode(0, 0, 0, 0, 0, 0, 0, 0)
            );
        }
        vm.expectRevert(revertMsg);
        IERC721(poolAddress).safeTransferFrom(user, farm, tokenId, lockup);
        if (
            keccak256(abi.encodePacked(revertMsg))
                == keccak256(abi.encodePacked(BaseFarm.NoLiquidityInPosition.selector))
        ) vm.clearMockedCalls();
    }

    function getPoolAddress() public view returns (address poolAddress) {
        poolAddress = INFTPoolFactory(NFT_POOL_FACTORY).getPool(LP_TOKEN);
    }

    function createFarmImplementation() public useKnownActor(owner) returns (address) {
        address camelotProxy;
        farmImpl = new Demeter_CamelotFarm();
        upgradeUtil = new UpgradeUtil();
        camelotProxy = upgradeUtil.deployErc1967Proxy(address(farmImpl));
        return camelotProxy;
    }

    function test_initialize_RevertWhen_camelotPairIsZero() public {
        address farm = createFarmImplementation();
        address[] memory rewardToken = rwdTokens;
        RewardTokenData[] memory rwdTokenData = new RewardTokenData[](rewardToken.length);
        for (uint8 i = 0; i < rewardToken.length; ++i) {
            rwdTokenData[i] = RewardTokenData(rewardToken[i], currentActor);
        }
        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.InvalidCamelotPoolConfig.selector));
        Demeter_CamelotFarm(farm).initialize(
            FARM_ID, block.timestamp, 0, address(factory), address(0), rwdTokenData, ROUTER, NFT_POOL_FACTORY
        );
    }

    function test_OnERC721Received_RevertWhen_NotACamelotNFT() public {
        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.NotACamelotNFT.selector));
        Demeter_CamelotFarm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_OnERC721Received_RevertWhen_NoData() public {
        address nftPool = Demeter_CamelotFarm(lockupFarm).nftContract();
        vm.startPrank(nftPool);
        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.NoData.selector));
        Demeter_CamelotFarm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_onNFTHarvest_RevertWhen_notNftPool() public {
        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.NotAllowed.selector));
        Demeter_CamelotFarm(lockupFarm).onNFTHarvest(address(0), address(0), 742, 1, 1);
    }

    function test_onNFTHarvest() public {
        address nftPool = Demeter_CamelotFarm(lockupFarm).nftContract();
        vm.startPrank(nftPool);
        bool harvested = Demeter_CamelotFarm(lockupFarm).onNFTHarvest(address(0), user, 742, 1, 1);
        assertEq(harvested, true);
    }

    function test_claimPoolRewards_RevertWhen_FarmIsClosed()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(7 days);
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        uint256 PoolRewards = Demeter_CamelotFarm(nonLockupFarm).computePoolRewards(0);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        Demeter_CamelotFarm(nonLockupFarm).claimPoolRewards(0);
        assertEq(0, PoolRewards);
    }

    function test_claimPoolRewards_RevertWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        Demeter_CamelotFarm(nonLockupFarm).claimPoolRewards(2);
    }

    function test_claimPoolRewards_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        skip(14 days);

        Demeter_CamelotFarm(nonLockupFarm).claimPoolRewards(1);
    }
}

contract CamelotIncreaseDepositTest is Demeter_CamelotFarmTest {
    using SafeERC20 for IERC20;

    function test_RevertWhen_FarmIsPaused() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsPaused.selector));
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(0, amounts, minAmounts);
    }

    function test_RevertWhen_InvalidDeposit() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        uint8 numDeposits = uint8(Demeter_CamelotFarm(nonLockupFarm).totalDeposits());
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(numDeposits + 1, amounts, minAmounts);
    }

    function test_RevertWhen_InvalidAmount() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 0;
        amounts[1] = 0;
        skip(7 days);

        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.InvalidAmount.selector));
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(1, amounts, minAmounts);
    }

    function test_RevertWhen_depositInCoolDown() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(lockupFarm, 1e22);
        IERC20(USDCe).forceApprove(lockupFarm, 1e22);
        Demeter_CamelotFarm(lockupFarm).initiateCooldown(1);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositIsInCooldown.selector));
        Demeter_CamelotFarm(lockupFarm).increaseDeposit(1, amounts, minAmounts);
    }

    function test_AmountA_noLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e4 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e23);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        RewardFund memory _rwdFund = Demeter_CamelotFarm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqBefore = _rwdFund.totalLiquidity;

        Subscription memory sub = Demeter_CamelotFarm(nonLockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(nonLockupFarm).COMMON_FUND_ID()
        );
        uint256[] memory _rewardDebtBefore = sub.rewardDebt;

        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        _rwdFund = Demeter_CamelotFarm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqAfter = _rwdFund.totalLiquidity;

        sub = Demeter_CamelotFarm(nonLockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(nonLockupFarm).COMMON_FUND_ID()
        );
        uint256[] memory _rewardDebtAfter = sub.rewardDebt;
        for (uint8 i; i < _rewardDebtBefore.length; i++) {
            assertTrue(_rewardDebtAfter[i] > _rewardDebtBefore[i]);
        }

        userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        rewardsClaimed = userDeposit.totalRewardsClaimed;

        assertTrue(totalFundLiqAfter > totalFundLiqBefore, "Failed to increase total liquidity");
        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_noLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256 depositId = 1;
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        rewardsClaimed = userDeposit.totalRewardsClaimed;

        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_lockupFarm() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        uint256[] memory totalFundLiquidity = new uint256[](2);
        uint256 depositId = 1;
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(lockupFarm, 1e22);
        IERC20(USDCe).forceApprove(lockupFarm, 1e22);
        RewardFund memory _rwdFund = Demeter_CamelotFarm(lockupFarm).getRewardFundInfo(0);
        totalFundLiquidity[0] = _rwdFund.totalLiquidity;
        Subscription memory sub = Demeter_CamelotFarm(lockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(lockupFarm).COMMON_FUND_ID()
        );
        uint256[] memory _commonRewardDebtBefore = sub.rewardDebt;
        sub = Demeter_CamelotFarm(lockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(lockupFarm).LOCKUP_FUND_ID()
        );
        uint256[] memory _lockupRewardDebtBefore = sub.rewardDebt;
        Demeter_CamelotFarm(lockupFarm).increaseDeposit(depositId, amounts, minAmounts);
        _rwdFund = Demeter_CamelotFarm(lockupFarm).getRewardFundInfo(0);
        totalFundLiquidity[1] = _rwdFund.totalLiquidity;
        sub = Demeter_CamelotFarm(lockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(lockupFarm).COMMON_FUND_ID()
        );
        uint256[] memory _commonRewardDebtAfter = sub.rewardDebt;
        sub = Demeter_CamelotFarm(lockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(lockupFarm).LOCKUP_FUND_ID()
        );
        uint256[] memory _lockupRewardDebtAfter = sub.rewardDebt;
        for (uint8 i; i < _commonRewardDebtBefore.length; i++) {
            assertTrue(_commonRewardDebtAfter[i] > _commonRewardDebtBefore[i]);
            assertTrue(_lockupRewardDebtAfter[i] > _lockupRewardDebtBefore[i]);
        }
        Deposit memory userDepositAfter = Demeter_CamelotFarm(lockupFarm).getDepositInfo(1);
        rewardsClaimed = userDepositAfter.totalRewardsClaimed;
        assertTrue(totalFundLiquidity[0] < totalFundLiquidity[1]);
        assertEq(IERC20(DAI).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(USDCe).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }
}

contract CamelotDecreaseDepositTest is Demeter_CamelotFarmTest {
    using SafeERC20 for IERC20;

    function test_RevertWhen_FarmIsClosed() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(1);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).closeFarm();
        vm.startPrank(user);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(0, liquidity, minAmounts);
    }

    function test_RevertWhen_InvalidDeposit() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        uint8 numDeposits = uint8(Demeter_CamelotFarm(nonLockupFarm).totalDeposits());
        Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(1);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(numDeposits + 1, liquidity, minAmounts);
    }

    function test_RevertWhen_ZeroAmount() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(DAI, user, amounts[0]);
        deal(USDCe, user, amounts[1]);
        IERC20(DAI).forceApprove(nonLockupFarm, 1e22);
        IERC20(USDCe).forceApprove(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(1, 0, minAmounts);
    }

    function test_lockupFarm() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(DAI).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(USDCe).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);

        Deposit memory userDeposit = Demeter_CamelotFarm(lockupFarm).getDepositInfo(1);
        uint256 liquidity = userDeposit.liquidity;
        vm.expectRevert(abi.encodeWithSelector(OperableDeposit.DecreaseDepositNotPermitted.selector));
        Demeter_CamelotFarm(lockupFarm).decreaseDeposit(1, liquidity - 1e4, minAmounts);
    }

    function test_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256 depositId = 1;
        Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        uint256 liquidity = userDeposit.liquidity;
        uint256[] memory BalanceBefore = new uint256[](2);

        //skipping 7 days
        skip(7 days);
        Demeter_CamelotFarm(nonLockupFarm).claimRewards(depositId);
        BalanceBefore[0] = IERC20(DAI).balanceOf(user);
        BalanceBefore[1] = IERC20(USDCe).balanceOf(user);
        RewardFund memory _rwdFund = Demeter_CamelotFarm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqBefore = _rwdFund.totalLiquidity;
        Subscription memory sub = Demeter_CamelotFarm(nonLockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(nonLockupFarm).COMMON_FUND_ID()
        );
        uint256[] memory _rewardDebtBefore = sub.rewardDebt;
        //We're not checking the data here
        vm.expectEmit(true, false, false, false);
        emit DepositDecreased(1, liquidity / 2);
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(depositId, liquidity / 2, minAmounts);
        Deposit memory userDepositAfter = Demeter_CamelotFarm(nonLockupFarm).getDepositInfo(depositId);
        _rwdFund = Demeter_CamelotFarm(nonLockupFarm).getRewardFundInfo(0);
        uint256 totalFundLiqAfter = _rwdFund.totalLiquidity;
        sub = Demeter_CamelotFarm(nonLockupFarm).getSubscriptionInfo(
            depositId, Demeter_CamelotFarm(nonLockupFarm).COMMON_FUND_ID()
        );
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
    Demeter_CamelotFarmTest,
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
    RecoverERC20Test,
    RecoverRewardFundsTest,
    GetDepositTest,
    MulticallTest,
    _SetupFarmTest
{
    function setUp() public override(Demeter_CamelotFarmTest, BaseFarmTest) {
        super.setUp();
    }
}
