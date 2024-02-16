// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {BaseUniV3ActiveLiquidityFarm} from "../../../../contracts/e721-farms/uniswapV3/BaseUniV3ActiveLiquidityFarm.sol";
import {Demeter_BaseUniV3ActiveLiquidityDeployer} from
    "../../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3ActiveLiquidityDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../BaseUniV3ActiveLiquidityFarm.t.sol";
import "../../../utils/UpgradeUtil.t.sol";

contract Demeter_UniV3ActiveLiquidityFarmTest is
    BaseFarmInheritTest,
    BaseE721FarmInheritTest,
    BaseUniV3FarmInheritTest,
    BaseFarmWithExpiryInheritTest,
    BaseUniV3ActiveLiquidityFarmInheritTest
{
    // Define variables
    string public FARM_NAME = "Demeter_UniV3_v4";

    function setUp() public virtual override(BaseUniV3ActiveLiquidityFarmTest, BaseUniV3FarmTest, BaseFarmTest) {
        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        // Mint a position to ensure that tick ranges is initialized
        super.setUp();
        _mintPosition(1, makeAddr("RANDOM-USER-DEPOSIT"));
    }

    function createFarm(uint256 startTime, bool lockup)
        public
        virtual
        override(BaseUniV3ActiveLiquidityFarmTest, BaseUniV3FarmTest, BaseFarmTest)
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
        Demeter_BaseUniV3ActiveLiquidityDeployer.FarmData memory _data = Demeter_BaseUniV3ActiveLiquidityDeployer
            .FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            uniswapPoolData: poolData,
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(uniV3ActiveLiqFarmDeployer), 1e22);
        address farm = uniV3ActiveLiqFarmDeployer.createFarm(_data);
        return farm;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt)
        public
        virtual
        override(BaseUniV3ActiveLiquidityFarmTest, BaseUniV3FarmTest, BaseFarmTest)
        returns (uint256)
    {
        currentActor = user;
        (uint256 tokenId, uint128 liquidity) = _mintPosition(baseAmt, currentActor);
        vm.startPrank(user);

        if (!locked) {
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, COMMON_FUND_ID);
        } else {
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, COMMON_FUND_ID);
            vm.expectEmit(address(farm));
            emit PoolSubscribed(BaseFarm(farm).totalDeposits() + 1, LOCKUP_FUND_ID);
        }
        vm.expectEmit(address(farm));
        emit Deposited(BaseFarm(farm).totalDeposits() + 1, currentActor, locked, liquidity);
        IERC721(NFPM).safeTransferFrom(currentActor, farm, tokenId, abi.encode(locked));
        vm.stopPrank();
        return liquidity;
    }
}
