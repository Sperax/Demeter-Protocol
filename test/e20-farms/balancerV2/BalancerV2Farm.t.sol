// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../E20Farm.t.sol";

import {E20Farm} from "../../../contracts/e20-farms/E20Farm.sol";
import {BalancerV2FarmDeployer} from "../../../contracts/e20-farms/balancerV2/BalancerV2FarmDeployer.sol";

struct JoinPoolRequest {
    address[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

interface IAsset {
// solhint-disable-previous-line no-empty-blocks
}

interface IBalancerV2Vault {
    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request)
        external
        payable;
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

interface ICustomOracle {
    function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) external;

    function getPrice() external view returns (uint256, uint256);
}

// RecoverERC20Test is replaced by RecoverERC20E20FarmTest
contract BalancerV2FarmTest is FarmInheritTest, ExpirableFarmInheritTest, E20FarmInheritTest {
    // Define variables
    bytes32 internal POOL_ID = 0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496; //Balancer Stable 4pool (4POOL-BPT)
    BalancerV2FarmDeployer public balancerV2FarmDeployer;

    string public FARM_ID = "Demeter_BalancerV2_v1";

    function setUp() public override {
        super.setUp();

        vm.startPrank(PROXY_OWNER);
        // Deploy and register farm deployer
        IFarmRegistry registry = IFarmRegistry(FARM_REGISTRY);
        balancerV2FarmDeployer = new BalancerV2FarmDeployer(FARM_REGISTRY, FARM_ID, BALANCER_VAULT);
        registry.registerFarmDeployer(address(balancerV2FarmDeployer));

        // Configure rewardTokens
        rwdTokens.push(USDCe);
        rwdTokens.push(DAI);

        invalidRewardToken = USDT;

        vm.stopPrank();

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
        /// Create Farm
        BalancerV2FarmDeployer.FarmData memory _data = BalancerV2FarmDeployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD_DAYS : 0,
            poolId: POOL_ID, //Balancer Stable 4pool (4POOL-BPT)
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(balancerV2FarmDeployer), 1e22);
        address farm = balancerV2FarmDeployer.createFarm(_data);

        assertEq(E20Farm(farm).farmId(), FARM_ID);

        return farm;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt)
        public
        override
        useKnownActor(user)
        returns (uint256)
    {
        // assertEq(currentActor, actors[0], "Wrong actor");
        address poolAddress = getPoolAddress();
        uint256 amt = baseAmt * 10 ** ERC20(poolAddress).decimals();
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(farm), amt);
        E20Farm(farm).deposit(amt, locked);
        return amt;
    }

    /// @notice Farm specific deposit logic
    function deposit(address farm, bool locked, uint256 baseAmt, bytes memory revertMsg)
        public
        override
        useKnownActor(user)
    {
        address poolAddress = getPoolAddress();
        uint256 amt = baseAmt * 10 ** ERC20(poolAddress).decimals();
        deal(poolAddress, currentActor, amt);
        ERC20(poolAddress).approve(address(farm), amt);

        vm.expectRevert(revertMsg);
        E20Farm(farm).deposit(amt, locked);
    }

    function getPoolAddress() public view override returns (address) {
        address poolAddress;
        (poolAddress,) = IBalancerV2Vault(BALANCER_VAULT).getPool(POOL_ID);
        return poolAddress;
    }
}
