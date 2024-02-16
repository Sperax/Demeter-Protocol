// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../E20Farm.t.sol";

import {E20Farm} from "../../../contracts/e20-farms/E20Farm.sol";
import {Demeter_BalancerFarm_Deployer} from "../../../contracts/e20-farms/balancer/Demeter_BalancerFarm_Deployer.sol";

struct JoinPoolRequest {
    address[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

interface IAsset {
// solhint-disable-previous-line no-empty-blocks
}

interface IBalancerVault {
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
contract BalancerFarmTest is FarmInheritTest, ExpirableFarmInheritTest, E20FarmInheritTest {
    // Define variables
    bytes32 internal POOL_ID = 0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496; //Balancer Stable 4pool (4POOL-BPT)
    Demeter_BalancerFarm_Deployer public balancerFarmDeployer;

    string public FARM_ID = "Demeter_BalancerV2_v1";

    function setUp() public override {
        super.setUp();

        vm.startPrank(PROXY_OWNER);
        // Deploy and register farm deployer
        FarmFactory factory = FarmFactory(DEMETER_FACTORY);
        balancerFarmDeployer = new Demeter_BalancerFarm_Deployer(DEMETER_FACTORY, FARM_ID, BALANCER_VAULT);
        factory.registerFarmDeployer(address(balancerFarmDeployer));

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
        Demeter_BalancerFarm_Deployer.FarmData memory _data = Demeter_BalancerFarm_Deployer.FarmData({
            farmAdmin: owner,
            farmStartTime: startTime,
            cooldownPeriod: lockup ? COOLDOWN_PERIOD : 0,
            poolId: POOL_ID, //Balancer Stable 4pool (4POOL-BPT)
            rewardData: rwdTokenData
        });

        // Approve Farm fee
        IERC20(FEE_TOKEN()).approve(address(balancerFarmDeployer), 1e22);
        address farm = balancerFarmDeployer.createFarm(_data);

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
        (poolAddress,) = IBalancerVault(BALANCER_VAULT).getPool(POOL_ID);
        return poolAddress;
    }
}
