// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.16;

import { Setup } from "./BaseTest.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import Contracts
import { FarmFactory } from "../../contracts/farmFactory.sol";
import { BaseFarmDeployer } from "../../contracts/BaseFarmDeployer.sol";
import { BaseFarm, RewardTokenData } from "../../contracts/BaseFarm.sol";
import { BaseE20Farm } from "../../contracts/e20-farms/BaseE20Farm.sol";
import { Demeter_BalancerFarm } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm.sol";
import { Demeter_BalancerFarm_Deployer } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";

interface ICustomOracle {
  function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) external;

  function getPrice() external view returns (uint256, uint256);
}

interface IVault {
  function mintBySpecifyingCollateralAmt(
    address _collateral,
    uint256 _collateralAmt,
    uint256 _minUSDSAmt,
    uint256 _maxSPAburnt,
    uint256 _deadline
  ) external;
}

abstract contract PreMigrationSetup is Setup {
  BaseE20Farm internal nonLockupFarm;
  BaseE20Farm internal lockupFarm;
  Demeter_BalancerFarm_Deployer internal balancerFarmDeployer;

  function setUp() public virtual override {
    super.setUp();
    setArbitrumFork();
    PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;
    OWNER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188;
    USDS_OWNER = 0x5b12d9846F8612E439730d18E1C12634753B1bF1;
    PROXY_OWNER = 0x6d5240f086637fb408c7F727010A10cf57D51B62;
    DEMETER_FACTORY = 0xC4fb09E0CD212367642974F6bA81D8e23780A659;
    BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    USDS_VAULT = 0xF783DD830A4650D2A8594423F123250652340E3f;
    vm.startPrank(PROXY_OWNER);
    FarmFactory factory = FarmFactory(DEMETER_FACTORY);

    balancerFarmDeployer = new Demeter_BalancerFarm_Deployer(
      DEMETER_FACTORY,
      BALANCER_VAULT,
      "Balancer Deployer"
    );
    factory.registerFarmDeployer(address(balancerFarmDeployer));

  }

  function createNonLockupFarm(uint256 startTime) public useActor(0) {
    RewardTokenData[] memory rwd_tkn = new RewardTokenData[](1);

    rwd_tkn[0] = RewardTokenData(USDCe, currentActor);

    Demeter_BalancerFarm_Deployer.FarmData
      memory _data = Demeter_BalancerFarm_Deployer.FarmData({
        farmAdmin: currentActor,
        farmStartTime: startTime,
        cooldownPeriod: 0,
        poolId: 0xb6911f80b1122f41c19b299a69dca07100452bf90002000000000000000004ba,
        rewardData: rwd_tkn
      });
    vm.stopPrank();
    // Minting USDs
    mintUSDs(1e10);

    vm.startPrank(USDS_OWNER);
    IERC20(USDS).transfer(currentActor, 1e21);
    vm.stopPrank();

    vm.startPrank(currentActor);
    IERC20(USDS).balanceOf(currentActor);
    IERC20(USDS).approve(address(balancerFarmDeployer), 1e22);
    nonLockupFarm = BaseE20Farm(balancerFarmDeployer.createFarm(_data));
  }

  function createLockupFarm(uint256 startTime) public useActor(1) {
    RewardTokenData[] memory rwd_tkn = new RewardTokenData[](1);

    rwd_tkn[0] = RewardTokenData(USDCe, currentActor);

    Demeter_BalancerFarm_Deployer.FarmData
      memory _data = Demeter_BalancerFarm_Deployer.FarmData({
        farmAdmin: currentActor,
        farmStartTime: startTime,
        cooldownPeriod: COOLDOWN_PERIOD,
        poolId: 0xb6911f80b1122f41c19b299a69dca07100452bf90002000000000000000004ba,
        rewardData: rwd_tkn
      });
    vm.stopPrank();
    // Minting USDs
    mintUSDs(1e10);

    vm.startPrank(USDS_OWNER);
    IERC20(USDS).transfer(currentActor, 1e21);
    vm.stopPrank();

    vm.startPrank(currentActor);
    IERC20(USDS).balanceOf(currentActor);
    IERC20(USDS).approve(address(balancerFarmDeployer), 1e22);
    lockupFarm = BaseE20Farm(balancerFarmDeployer.createFarm(_data));
  }

  function mintUSDs(uint256 amountIn) public {
    vm.startPrank(USDS_OWNER);

    deal(address(USDCe), USDS_OWNER, amountIn);

    IERC20(USDCe).approve(USDS_VAULT, amountIn);
    IVault(USDS_VAULT).mintBySpecifyingCollateralAmt(
      USDCe,
      amountIn,
      0,
      0,
      block.timestamp + 1200
    );
    vm.stopPrank();
  }

  //   function createFarm_without_deployer() public useActor(0){
  //     RewardTokenData[] memory rwd_tkn = new RewardTokenData[](1);

  //     rwd_tkn[0] = RewardTokenData(USDCe, currentActor);

  //     Demeter_BalancerFarm_Deployer.FarmData
  //       memory _data = Demeter_BalancerFarm_Deployer.FarmData({
  //         farmAdmin: currentActor,
  //         farmStartTime: block.timestamp,
  //         cooldownPeriod: 21,
  //         poolId: 0xb6911f80b1122f41c19b299a69dca07100452bf90002000000000000000004ba,
  //         rewardData: rwd_tkn
  //       });

  //     // balancerFarm =  BaseFarm(_data);
  // }
}
