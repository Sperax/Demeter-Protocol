// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseFarm.t.sol";
import {INFTPoolFactory, IPositionHelper, INFTPool} from "../../contracts/camelot/interfaces/CamelotInterfaces.sol";
import "../../contracts/camelot/Demeter_CamelotFarm_Deployer.sol";
import "../../contracts/camelot/Demeter_CamelotFarm.sol";
import "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract Demeter_CamelotFarmTest is
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
    // IncreaseDepositTest,
    // WithdrawPartiallyTest,
    RecoverERC20Test,
    RecoverRewardFundsTest,
    _SetupFarmTest
{
    using SafeERC20 for IERC20;

    address public constant NFT_POOL_FACTORY = 0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d;
    address public constant CAMELOT_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;
    address public constant LP_TOKEN = 0x01efEd58B534d7a7464359A6F8d14D986125816B;
    // address public constant ASSET_1 = 0x2CaB3abfC1670D1a452dF502e216a66883cDf079;
    // address public constant ASSET_2 = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public constant ASSET_1 = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant ASSET_2 = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant POSITION_HELPER = 0xe458018Ad4283C90fB7F5460e24C4016F81b8175;
    address public constant ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    Demeter_CamelotFarm_Deployer internal demeter_camelotFarm_deployer;

    function setUp() public override {
        super.setUp();

        vm.startPrank(PROXY_OWNER);
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        demeter_camelotFarm_deployer = new Demeter_CamelotFarm_Deployer(DEMETER_FACTORY, CAMELOT_FACTORY);
        factory.registerFarmDeployer(address(demeter_camelotFarm_deployer));
        vm.stopPrank();

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

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
            Demeter_CamelotFarm_Deployer.CamelotPoolData({tokenA: ASSET_1, tokenB: ASSET_2});
        /// Create Farm
        Demeter_CamelotFarm_Deployer.FarmData memory _data = Demeter_CamelotFarm_Deployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            camelotPoolData: _poolData,
            rewardData: rwdTokenData
        });
        IERC20(FEE_TOKEN()).approve(address(demeter_camelotFarm_deployer), 1e20);
        emit log_named_uint("Owner balance", IERC20(FEE_TOKEN()).balanceOf(owner));
        address farm = demeter_camelotFarm_deployer.createFarm(_data);
        emit log_named_address("Created farm address", farm);

        assertEq(Demeter_CamelotFarm(farm).FARM_ID(), "Demeter_Camelot_v1");
        return farm;
    }

    function deposit(address farm, bool locked, uint256 amt) public override useKnownActor(user) {
        bytes memory lockup = locked ? abi.encode(true) : abi.encode(false);
        uint256 amt1 = amt * 10 ** ERC20(ASSET_1).decimals();
        deal(ASSET_1, user, amt1);
        uint256 amt2 = amt * 10 ** ERC20(ASSET_2).decimals();
        deal(ASSET_2, user, amt2);
        IERC20(ASSET_1).safeIncreaseAllowance(POSITION_HELPER, amt1);
        IERC20(ASSET_2).safeIncreaseAllowance(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            ASSET_1, ASSET_2, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(getPoolAddress()), 0
        );
        uint256 tokenId = INFTPool(getPoolAddress()).lastTokenId();
        IERC721(getPoolAddress()).safeTransferFrom(user, farm, tokenId, lockup);
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
        uint256 amt1 = amt * 10 ** ERC20(ASSET_1).decimals();
        deal(ASSET_1, user, amt1);
        uint256 amt2 = amt * 10 ** ERC20(ASSET_2).decimals();
        deal(ASSET_2, user, amt2);
        IERC20(ASSET_1).forceApprove(POSITION_HELPER, amt1);
        IERC20(ASSET_2).forceApprove(POSITION_HELPER, amt2);
        IPositionHelper(POSITION_HELPER).addLiquidityAndCreatePosition(
            ASSET_1, ASSET_2, amt1, amt2, amt1 / 10, amt2 / 10, block.timestamp, user, INFTPool(getPoolAddress()), 0
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

    function getPoolAddress() public view override returns (address poolAddress) {
        poolAddress = INFTPoolFactory(NFT_POOL_FACTORY).getPool(LP_TOKEN);
    }

    function test_increaseDeposit_revertsWhen_FarmIsPaused()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();

        skip(7 days);
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsPaused.selector));
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(0, amounts, minAmounts);
    }

    function test_increaseDeposit_revertsWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();
        uint8 numDeposits = uint8(Demeter_CamelotFarm(nonLockupFarm).getNumDeposits(user));
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(numDeposits + 1, amounts, minAmounts);
    }

    function test_increaseDeposit_noLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDeposit(user, 0);
        uint256 tokenId = userDeposit.tokenId;
        uint256 liquidity = userDeposit.liquidity;
        vm.expectEmit(true, false, false, true);
        emit DepositIncreased(user, tokenId, liquidity, minAmounts[0], minAmounts[1]);
        Demeter_CamelotFarm(nonLockupFarm).increaseDeposit(0, amounts, minAmounts);
        userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDeposit(user, 0);
        rewardsClaimed = userDeposit.totalRewardsClaimed;
        console.log("rewardsClaimed[0]: %s", rewardsClaimed[0]);

        assertEq(IERC20(ASSET_1).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(ASSET_2).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_increaseDeposit_lockupFarm() public depositSetup(lockupFarm, false) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        uint256[] memory rewardsClaimed = new uint256[](2);
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(lockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(lockupFarm, 1e22);
        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(lockupFarm).getDeposit(currentActor, 0);
        uint256 tokenId = userDeposit.tokenId;
        uint256 liquidity = userDeposit.liquidity;
        vm.expectEmit(true, false, false, true);
        emit DepositIncreased(user, tokenId, liquidity, minAmounts[0], minAmounts[1]);
        Demeter_CamelotFarm(lockupFarm).increaseDeposit(0, amounts, minAmounts);
        Demeter_CamelotFarm.Deposit memory userDepositAfter =
            Demeter_CamelotFarm(lockupFarm).getDeposit(currentActor, 0);
        rewardsClaimed = userDepositAfter.totalRewardsClaimed;
        console.log("rewardsClaimed[0]: %s", rewardsClaimed[0]);
        assertEq(IERC20(ASSET_1).balanceOf(user) + minAmounts[0], amounts[0] + rewardsClaimed[0]);
        assertEq(IERC20(ASSET_2).balanceOf(user) + minAmounts[1], amounts[1] + rewardsClaimed[1]);
    }

    function test_decreaseDeposit_revertsWhen_FarmIsClosed()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();
        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDeposit(currentActor, 0);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        vm.startPrank(BaseFarm(nonLockupFarm).owner());
        BaseFarm(nonLockupFarm).closeFarm();
        changePrank(user);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.FarmIsClosed.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(0, liquidity, minAmounts);
    }

    function test_decreaseDeposit_revertsWhen_InvalidDeposit()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();
        uint8 numDeposits = uint8(Demeter_CamelotFarm(nonLockupFarm).getNumDeposits(user));
        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDeposit(currentActor, 0);
        uint256 liquidity = userDeposit.liquidity;
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.DepositDoesNotExist.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(numDeposits + 1, liquidity, minAmounts);
    }

    function test_decreaseDeposit_revertsWhen_ZeroAmount()
        public
        depositSetup(nonLockupFarm, false)
        useKnownActor(user)
    {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();
        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(nonLockupFarm).getDepositAmounts(amounts[0], amounts[1]);
        deal(ASSET_1, user, amounts[0]);
        deal(ASSET_2, user, amounts[1]);
        IERC20(ASSET_1).safeIncreaseAllowance(nonLockupFarm, 1e22);
        IERC20(ASSET_2).safeIncreaseAllowance(nonLockupFarm, 1e22);
        vm.expectRevert(abi.encodeWithSelector(BaseFarm.CannotWithdrawZeroAmount.selector));
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(0, 0, minAmounts);
    }

    function test_decreaseDeposit_lockupFarm() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256[2] memory amounts = [uint256(0), 0];
        uint256[2] memory minAmounts = [uint256(0), 0];
        amounts[0] = 1e3 * 10 ** ERC20(ASSET_1).decimals();
        amounts[1] = 1e3 * 10 ** ERC20(ASSET_2).decimals();

        skip(7 days);
        (minAmounts[0], minAmounts[1]) = Demeter_CamelotFarm(lockupFarm).getDepositAmounts(amounts[0], amounts[1]);

        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(lockupFarm).getDeposit(currentActor, 0);
        uint256 liquidity = userDeposit.liquidity;
        vm.expectRevert(abi.encodeWithSelector(Demeter_CamelotFarm.DecreaseDepositNotPermitted.selector));
        Demeter_CamelotFarm(lockupFarm).decreaseDeposit(0, liquidity - 1e4, minAmounts);
    }

    function test_decreaseDeposit_nonLockupFarm() public depositSetup(nonLockupFarm, false) useKnownActor(user) {
        uint256[2] memory minAmounts = [uint256(0), 0];
        Demeter_CamelotFarm.Deposit memory userDeposit = Demeter_CamelotFarm(nonLockupFarm).getDeposit(currentActor, 0);
        uint256[] memory rewardsClaimed = new uint256[](2);
        uint256 tokenId = userDeposit.tokenId;
        uint256 tokenIdLog;
        uint256 liquidity = userDeposit.liquidity;
        uint256 liquidityLog;
        uint256 amt1;
        uint256 amt2;
        uint256 amt1Decreased;
        uint256 amt2Decreased;
        uint256[] memory BalanceBefore = new uint256[](2);

        //skipping 7 days
        skip(7 days);
        BalanceBefore[0] = IERC20(ASSET_1).balanceOf(user);
        BalanceBefore[1] = IERC20(ASSET_2).balanceOf(user);
        //We're not checking the data here
        vm.expectEmit(true, false, false, false);
        emit DepositDecreased(user, tokenId, liquidity / 2, 0, 0);
        //Checking Data here
        // Fetching the logs in order to get the amounts.
        vm.recordLogs();
        Demeter_CamelotFarm(nonLockupFarm).decreaseDeposit(0, liquidity / 2, minAmounts);
        Demeter_CamelotFarm.Deposit memory userDepositAfter =
            Demeter_CamelotFarm(nonLockupFarm).getDeposit(currentActor, 0);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint8 j = 0; j < logs.length; ++j) {
            // Camelot Pair Burn Event
            if (logs[j].topics[0] == 0xdccd412f0b1252819cb1fd330b93224ca42612892bb3f4f789976e6d81936496) {
                (amt1, amt2) = abi.decode(logs[j].data, (uint256, uint256));
            }
        }
        // Demeter Deposit Decreased
        (tokenIdLog, liquidityLog, amt1Decreased, amt2Decreased) =
            abi.decode(logs[17].data, (uint256, uint256, uint256, uint256));
        rewardsClaimed = userDepositAfter.totalRewardsClaimed;
        //Asserting Data
        assertEq(amt1Decreased, amt1);
        assertEq(amt2Decreased, amt2);
        assertEq(tokenIdLog, tokenId);
        assertEq(liquidityLog, liquidity / 2);
        // Asserting Assets Balances
        assertEq(IERC20(ASSET_1).balanceOf(user), BalanceBefore[0] + rewardsClaimed[0] + amt1Decreased);
        assertEq(IERC20(ASSET_2).balanceOf(user), BalanceBefore[1] + rewardsClaimed[1] + amt2Decreased);
    }
}
