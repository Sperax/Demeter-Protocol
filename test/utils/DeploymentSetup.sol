// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.16;

import { Setup } from "./BaseTest.sol";
import { UpgradeUtil } from "./UpgradeUtil.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// import Contracts
import { FarmFactory } from "../../contracts/farmFactory.sol";
import { BaseFarmDeployer } from "../../contracts/BaseFarmDeployer.sol";
import { BaseFarm } from "../../contracts/BaseFarm.sol";
import { Demeter_BalancerFarm } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm.sol";
import { Demeter_BalancerFarm_Deployer } from "../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";

interface ICustomOracle {
  function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) external;

  function getPrice() external view returns (uint256, uint256);
}

abstract contract PreMigrationSetup is Setup {
  struct PriceFeedData {
    address token;
    address source;
    bytes msgData;
  }

  UpgradeUtil internal upgradeUtil;
  BaseFarmDeployer internal baseFarmDeployer;
  BaseFarm internal baseFarm;
  Demeter_BalancerFarm internal balancerFarm;
  Demeter_BalancerFarm_Deployer internal balancerFarmDeployer;

  function setUp() public virtual override {
    super.setUp();

    setArbitrumFork();

    OWNER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188;
    PROXY_OWNER = 0x6d5240f086637fb408c7F727010A10cf57D51B62;
    DEMETER_FACTORY = 0xC4fb09E0CD212367642974F6bA81D8e23780A659;
    BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    CAMELOT_NFT_FACTORY = 0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d;
    CAMELOT_POSITION_HELPER = 0xe458018Ad4283C90fB7F5460e24C4016F81b8175;

    vm.startPrank(PROXY_OWNER);

    FarmFactory factoryImpl = new FarmFactory();
    DEMETER_FACTORY = upgradeUtil.deployErc1967Proxy(address(factoryImpl));

    FarmFactory factory = FarmFactory(DEMETER_FACTORY);

    balancerFarmDeployer = new Demeter_BalancerFarm_Deployer(
      DEMETER_FACTORY,
      BALANCER_VAULT,
      "Balancer Deployer"
    );
   factory.registerFarmDeployer(address(balancerFarmDeployer));


  balancerFarmDeployer.createFarm();


    //     // deploy Farm Factory
    //     USDs usdsImpl = new USDs();
    //     vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
    //     ProxyAdmin(PROXY_ADMIN).upgrade(
    //       ITransparentUpgradeableProxy(USDS),
    //       address(usdsImpl)
    //     );
    //     vm.startPrank(OWNER);
    //     // Deploy
    //     VaultCore vaultImpl = new VaultCore();
    //     VAULT = upgradeUtil.deployErc1967Proxy(address(vaultImpl));
    //     USDs(USDS).updateVault(VAULT);

    //     VaultCore vault = VaultCore(VAULT);
    //     vault.initialize();
    //     CollateralManager collateralManager = new CollateralManager(VAULT);

    //     ORACLE = address(new MasterPriceOracle());
    //     FEE_CALCULATOR = address(new FeeCalculator());
    //     COLLATERAL_MANAGER = address(collateralManager);
    //     FEE_VAULT = 0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3;
    //     DRIPPER = address(new Dripper(VAULT, 7 days));
    //     REBASE_MANAGER = address(
    //       new RebaseManager(VAULT, DRIPPER, 1 days, 1000, 800)
    //     );

    //     vault.updateCollateralManager(COLLATERAL_MANAGER);
    //     vault.updateFeeCalculator(FEE_CALCULATOR);
    //     vault.updateOracle(ORACLE);
    //     vault.updateRebaseManager(REBASE_MANAGER);
    //     vault.updateFeeVault(FEE_VAULT);

    //     vstOracle = new VSTOracle();
    //     masterOracle = MasterPriceOracle(ORACLE);
    //     // A pre-requisite for initializing SPA and USDs oracles
    //     deployAndConfigureChainlink();
    //     masterOracle.updateTokenPriceFeed(
    //       USDCe,
    //       address(chainlinkOracle),
    //       abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, USDCe)
    //     );
    //     spaOracle = deployCode(
    //       "SPAOracle.sol:SPAOracle",
    //       abi.encode(address(masterOracle), USDCe, 10000, 600, 70)
    //     );
    //     ICustomOracle(address(spaOracle)).updateDIAParams(70, type(uint128).max);
    //     usdsOracle = deployCode(
    //       "USDsOracle.sol",
    //       abi.encode(address(masterOracle), USDCe, 500, 600)
    //     );

    //     updatePriceFeeds();

    //     ICollateralManager.CollateralBaseData memory _data = ICollateralManager
    //       .CollateralBaseData({
    //         mintAllowed: true,
    //         redeemAllowed: true,
    //         allocationAllowed: true,
    //         baseFeeIn: 0,
    //         baseFeeOut: 500,
    //         downsidePeg: 9800,
    //         desiredCollateralComposition: 5000
    //       });

    //     address stargateRouter = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    //     address stg = 0x6694340fc020c5E6B96567843da2df01b2CE1eb6;
    //     address stargateFarm = 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176;
    //     StargateStrategy stargateStrategyImpl = new StargateStrategy();
    //     address stargateStrategyProxy = upgradeUtil.deployErc1967Proxy(
    //       address(stargateStrategyImpl)
    //     );
    //     vm.makePersistent(stargateStrategyProxy);
    //     stargateStrategy = StargateStrategy(stargateStrategyProxy);
    //     stargateStrategy.initialize(
    //       stargateRouter,
    //       VAULT,
    //       stg,
    //       stargateFarm,
    //       20,
    //       20
    //     );
    //     stargateStrategy.setPTokenAddress(
    //       USDCe,
    //       0x892785f33CdeE22A30AEF750F285E18c18040c3e,
    //       1,
    //       0,
    //       0
    //     );

    //     address aavePoolProvider = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    //     AaveStrategy aaveStrategyImpl = new AaveStrategy();
    //     address aaveStrategyProxy = upgradeUtil.deployErc1967Proxy(
    //       address(aaveStrategyImpl)
    //     );
    //     vm.makePersistent(aaveStrategyProxy);
    //     aaveStrategy = AaveStrategy(aaveStrategyProxy);
    //     aaveStrategy.initialize(aavePoolProvider, VAULT);
    //     aaveStrategy.setPTokenAddress(
    //       USDCe,
    //       0x625E7708f30cA75bfd92586e17077590C60eb4cD,
    //       0
    //     );

    //     collateralManager.addCollateral(USDCe, _data);
    //     collateralManager.addCollateralStrategy(
    //       USDCe,
    //       address(stargateStrategy),
    //       3000
    //     );
    //     collateralManager.addCollateralStrategy(USDCe, address(aaveStrategy), 4000);
    //     collateralManager.updateCollateralDefaultStrategy(
    //       USDCe,
    //       address(stargateStrategy)
    //     );
    //     AAVE_STRATEGY = address(aaveStrategy);
    //     STARGATE_STRATEGY = address(stargateStrategy);
    //     vm.stopPrank();
    //   }

    //   function deployAndConfigureChainlink() private {
    //     ChainlinkOracle.SetupTokenData[]
    //       memory chainlinkFeeds = new ChainlinkOracle.SetupTokenData[](3);
    //     chainlinkFeeds[0] = ChainlinkOracle.SetupTokenData(
    //       USDCe,
    //       ChainlinkOracle.TokenData(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 1e8)
    //     );
    //     chainlinkFeeds[1] = ChainlinkOracle.SetupTokenData(
    //       FRAX,
    //       ChainlinkOracle.TokenData(0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8, 1e8)
    //     );
    //     chainlinkFeeds[2] = ChainlinkOracle.SetupTokenData(
    //       DAI,
    //       ChainlinkOracle.TokenData(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB, 1e8)
    //     );
    //     chainlinkOracle = new ChainlinkOracle(chainlinkFeeds);
    //   }

    //   function updatePriceFeeds() private {
    //     PriceFeedData[] memory feedData = new PriceFeedData[](5);
    //     feedData[0] = PriceFeedData(
    //       FRAX,
    //       address(chainlinkOracle),
    //       abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, FRAX)
    //     );
    //     feedData[1] = PriceFeedData(
    //       DAI,
    //       address(chainlinkOracle),
    //       abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, DAI)
    //     );
    //     feedData[2] = PriceFeedData(
    //       VST,
    //       address(vstOracle),
    //       abi.encodeWithSelector(VSTOracle.getPrice.selector)
    //     );
    //     feedData[3] = PriceFeedData(
    //       SPA,
    //       spaOracle,
    //       abi.encodeWithSelector(ICustomOracle.getPrice.selector)
    //     );
    //     feedData[4] = PriceFeedData(
    //       USDS,
    //       usdsOracle,
    //       abi.encodeWithSelector(ICustomOracle.getPrice.selector)
    //     );
    //     // feedData[0] = PriceFeedData(USDCe, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, USDCe));
    //     for (uint8 i = 0; i < feedData.length; ++i) {
    //       masterOracle.updateTokenPriceFeed(
    //         feedData[i].token,
    //         feedData[i].source,
    //         feedData[i].msgData
    //       );
    //     }
  }
}
