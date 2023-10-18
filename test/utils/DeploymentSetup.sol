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

interface IBalancerVault {
  enum PoolSpecialization {
    GENERAL,
    MINIMAL_SWAP_INFO,
    TWO_TOKEN
  }

  function getPool(bytes32 poolId)
    external
    view
    returns (address, PoolSpecialization);

  function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
      IERC20[] memory tokens,
      uint256[] memory balances,
      uint256 lastChangeBlock
    );
}

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
    SPA_MANAGER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188;
    //POOL_ID = 0x848a7ff84cf73d2534c3dac6ab381e177a1cff240001000000000000000004bb; //33108-33WETH-33USDC (33108-33W...)
    POOL_ID = 0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496; //Balancer Stable 4pool (4POOL-BPT)
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
        poolId: POOL_ID, //Balancer Stable 4pool (4POOL-BPT)
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
        poolId: POOL_ID,
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

  function addRewards(BaseE20Farm farm) public {
    address[] memory rewardTokens = farm.getRewardTokens();
    uint256 rwdAmt;

    for (uint8 i; i < rewardTokens.length; ++i) {
      if (farm.cooldownPeriod() == 0) {
        vm.startPrank(actors[0]);
        rwdAmt = 1000000 * 10**ERC20(rewardTokens[i]).decimals();
        deal(address(rewardTokens[i]), actors[0], rwdAmt);
        IERC20(rewardTokens[i]).approve(address(farm), 2 * rwdAmt);
        IERC20(rewardTokens[i]).balanceOf(actors[0]);
        farm.addRewards(rewardTokens[i], rwdAmt);
      } else {
        vm.startPrank(actors[1]);
        rwdAmt = 1000000 * 10**ERC20(rewardTokens[i]).decimals();
        deal(address(rewardTokens[i]), actors[1], rwdAmt);
        IERC20(rewardTokens[i]).approve(address(farm), 2 * rwdAmt);
        IERC20(rewardTokens[i]).balanceOf(actors[1]);
        farm.addRewards(rewardTokens[i], rwdAmt);
      }
    }
  }

  function setRewardRates(BaseE20Farm farm) public {
    if (farm.cooldownPeriod() == 0) {
      vm.startPrank(actors[0]);
      uint256[] memory rwdRate = new uint256[](1);
      address[] memory rewardTokens = farm.getRewardTokens();
      uint256[] memory oldRewardRate = new uint256[](1);
      for (uint8 i; i < rewardTokens.length; ++i) {
        oldRewardRate = farm.getRewardRates(rewardTokens[i]);
        rwdRate[0] = 1 * 10**ERC20(rewardTokens[i]).decimals();
        if (rewardTokens[i] == SPA) {
          vm.startPrank(SPA_MANAGER);
        } else {
          vm.startPrank(actors[0]);
        }
        farm.setRewardRate(rewardTokens[i], rwdRate);
      }
    } else {
      vm.startPrank(actors[1]);
      uint256[] memory rwdRate = new uint256[](2);
      address[] memory rewardTokens = farm.getRewardTokens();
      uint256[] memory oldRewardRate = new uint256[](2);
      for (uint8 i; i < rewardTokens.length; ++i) {
        oldRewardRate = farm.getRewardRates(rewardTokens[i]);
        rwdRate[0] = 1 * 10**ERC20(rewardTokens[i]).decimals();
        rwdRate[1] = 2 * 10**ERC20(rewardTokens[i]).decimals();
        if (rewardTokens[i] == SPA) {
          vm.startPrank(SPA_MANAGER);
        } else {
          vm.startPrank(actors[1]);
        }
        farm.setRewardRate(rewardTokens[i], rwdRate);
      }
    }
  }

  function deposit(BaseE20Farm farm, bool locked) public useActor(5) {
    address poolAddress;
    (poolAddress, ) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
    uint256 amt = 1000 * 10**ERC20(poolAddress).decimals();
    deal(poolAddress, currentActor, amt);
    ERC20(poolAddress).approve(address(farm), amt);
    farm.deposit(amt, locked);
  }
}
