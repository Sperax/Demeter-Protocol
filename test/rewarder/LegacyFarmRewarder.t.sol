// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CamelotV2Farm} from "../../contracts/e721-farms/camelotV2/CamelotV2Farm.sol";
import {RewarderFactory} from "../../contracts/rewarder/RewarderFactory.sol";
import {Rewarder, LegacyFarmRewarder, IFarm} from "../../contracts/rewarder/LegacyFarmRewarder.sol";
import {RewarderTest} from "./Rewarder.t.sol";

interface ILegacyFarm {
    function rewardData(address token) external view returns (address manager, uint8 id, uint256 accRwdBal);
    function getRewardRates(address token) external view returns (uint256[] memory);
    function updateTokenManager(address rwdToken, address tknManager) external;
}

contract LegacyFarmRewarderTest is RewarderTest {
    LegacyFarmRewarder public legacyRewarder;
    address[] private farms;
    mapping(address => LegacyFarmRewarder.FarmRewardConfigInput) private farmRewardConfigs;

    function setUp() public override {
        super.setUp();
        _addFarms();
        vm.prank(PROXY_OWNER);
        legacyRewarder = new LegacyFarmRewarder(SPA, ORACLE, PROXY_OWNER, address(rewarderFactory), UNISWAP_UTILS);
        rewardManager = makeAddr("Reward manager");
        address[] memory _baseTokens = new address[](1);
        _baseTokens[0] = USDS;
        uint256 farmsLen = farms.length;
        deal(SPA, address(legacyRewarder), 1e30);
        for (uint8 i; i < farmsLen;) {
            (address tokenManager,,) = ILegacyFarm(farms[i]).rewardData(SPA);
            vm.prank(tokenManager);
            ILegacyFarm(farms[i]).updateTokenManager(SPA, address(legacyRewarder));
            farmRewardConfigs[farms[i]] = Rewarder.FarmRewardConfigInput({
                apr: i * 1e9,
                maxRewardRate: type(uint256).max,
                baseTokens: _baseTokens,
                nonLockupRewardPer: 5000
            });
            if (i > 1) {
                vm.prank(PROXY_OWNER);
                legacyRewarder.updateRewardConfig(farms[i], farmRewardConfigs[farms[i]], true);
            } else {
                vm.prank(PROXY_OWNER);
                legacyRewarder.updateRewardConfig(farms[i], farmRewardConfigs[farms[i]], false);
            }
            legacyRewarder.calibrateReward(farms[i]);
            unchecked {
                ++i;
            }
        }
    }

    function test_printStats() public view {
        uint256 farmsLen = farms.length;
        for (uint8 i; i < farmsLen;) {
            (uint256 apr, uint256 rewardRate,,) = legacyRewarder.farmRewardConfigs(farms[i]);
            (address[] memory assets, uint256[] memory amounts) = legacyRewarder.getTokenAmounts(farms[i]);
            uint256[] memory rwdRates = ILegacyFarm(farms[i]).getRewardRates(SPA);
            console.log("*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*");
            console.log("* Farm %s           : %s", i + 1, farms[i]);
            console.log("* APR              : %s", apr / 1e8, "%");
            console.log("* RewardRate(rwdr) : %s (in wei)", rewardRate);
            uint256 rwdRate;
            if (rwdRates.length == 2) {
                console.log("* RewardRate(NL)   : %s (in wei)", rwdRates[0]);
                console.log("* RewardRate(L)    : %s (in wei)", rwdRates[1]);
                rwdRate = rwdRates[0] + rwdRates[1];
            } else {
                console.log("* RewardRate(NL)   : %s (in wei)", rwdRates[0]);
                rwdRate = rwdRates[0];
            }
            console.log("* RewardRate(farm) : %s (in wei)", rwdRate);
            uint256 _usdsAmt = assets[0] == USDS ? amounts[0] : amounts[1];
            console.log("* USDS amount      : %s.0 USDS (Precision adjusted)", _usdsAmt / 1e18);
            console.log("* Weekly rewards   : %s.0 SPA (Precision adjusted)", (rewardRate * 1 weeks) / 1e18);
            console.log("* Reward Balance   : %s.0 SPA (Precision adjusted)", ERC20(SPA).balanceOf(farms[i]) / 1e18);
            console.log("* Annual rewards   : %s.0 SPA (Precision adjusted)", (rewardRate * 365 days) / 1e18);
            console.log("* Total rwdRate    : %s", legacyRewarder.totalRewardRate());
            console.log("* Amounts are %s and %s", amounts[0], amounts[1]);
            console.log("*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*");
            console.log();
            unchecked {
                ++i;
            }
        }
        console.log("* Total rwdRate    : %s", legacyRewarder.totalRewardRate());
    }

    function _addFarms() private {
        farms.push(0x4073D8479D67851Ae90332d6600d6BF1211703ee);
        farms.push(0x50f37e7D81f6d24E1ee9fb252Dbbc337F54438e6);
        farms.push(0xF6EE4989D8e6B7C316E10cCe7A3e6D596f3A5F3C);
        farms.push(0x17EbdD5Eae0c56d251BF617536643916EA2F4c7b);
        farms.push(0xeBc45B3b23A3Bae76270A51f7196e55Cba843CAB);
    }
}
