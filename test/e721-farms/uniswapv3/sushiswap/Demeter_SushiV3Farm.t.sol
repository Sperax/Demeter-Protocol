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
import "../../../utils/UpgradeUtil.t.sol";

contract Demeter_SushiV3FarmTest is BaseUniV3FarmTest {
    // Define variables
    string public constant FARM_NAME = "Demeter_SushiV3_v1";

    function setUp() public virtual override {
        NFPM = SUSHISWAP_NFPM;
        UNIV3_FACTORY = SUSHISWAP_FACTORY;
        SWAP_ROUTER = SUSHISWAP_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        super.setUp();
    }
}

contract Demeter_SushiV3FarmInheritTest is
    Demeter_SushiV3FarmTest,
    DepositTest,
    WithdrawTest,
    WithdrawWithExpiryTest,
    ClaimRewardsTest,
    GetRewardFundInfoTest,
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
    UpdateCoolDownPeriodTest,
    CloseFarmTest,
    _SetupFarmTest,
    InitializeTest,
    OnERC721ReceivedTest,
    WithdrawAdditionalTest,
    ClaimUniswapFeeTest,
    RecoverERC20Test,
    NFTDepositTest,
    IncreaseDepositTest,
    DecreaseDepositTest
{
    function setUp() public override(Demeter_SushiV3FarmTest, BaseUniV3FarmTest, BaseFarmTest) {
        Demeter_SushiV3FarmTest.setUp();
    }
}
