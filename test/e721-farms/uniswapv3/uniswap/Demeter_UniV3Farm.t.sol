// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {BaseUniV3Farm} from "../../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {Demeter_BaseUniV3FarmDeployer} from
    "../../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3FarmDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../BaseUniV3Farm.t.sol";

contract Demeter_UniV3FarmTest is BaseUniV3FarmTest {
    // Define variables
    string public FARM_NAME = "Demeter_UniV3_v4";

    function setUp() public virtual override {
        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        super.setUp();
    }
}

contract Demeter_UniV3FarmTestInheritTest is
    Demeter_UniV3FarmTest,
    DepositTest,
    WithdrawTest,
    WithdrawWithExpiryTest,
    ClaimRewardsTest,
    GetRewardFundInfoTest,
    RecoverERC20Test,
    RecoverRewardFundsTest,
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
    CloseFarmTest,
    UpdateCoolDownPeriodTest,
    _SetupFarmTest,
    InitializeTest,
    OnERC721ReceivedTest,
    WithdrawAdditionalTest,
    ClaimUniswapFeeTest,
    NFTDepositTest,
    IncreaseDepositTest,
    DecreaseDepositTest
{
    function setUp() public override(Demeter_UniV3FarmTest, BaseUniV3FarmTest, BaseFarmTest) {
        Demeter_UniV3FarmTest.setUp();
    }
}
