// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseFarm.t.sol";
import {INFTPoolFactory, IPositionHelper, INFTPool} from "../../contracts/camelot/interfaces/CamelotInterfaces.sol";
import "../../contracts/camelot/Demeter_CamelotFarm_Deployer.sol";
import "../../contracts/camelot/Demeter_CamelotFarm.sol";

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
}
