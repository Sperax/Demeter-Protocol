// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Farm, RewardTokenData} from "../contracts/Farm.sol";
import {E20Farm} from "../contracts/e20-farms/E20Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {FarmRegistry, IFarmRegistry, OwnableUpgradeable} from "../contracts/FarmRegistry.sol";
import {FarmDeployer} from "../contracts/FarmDeployer.sol";
import {UpgradeUtil} from "../test/utils/UpgradeUtil.t.sol";

abstract contract FarmRegistryTest is TestNetworkConfig {
    UpgradeUtil internal upgradeUtil;
    FarmRegistry public registryImp;
    uint256 public constant FEE_AMOUNT = 1e20;
    uint256 public constant FEE_AMOUNT_LOWER_BOUND = 1e18;
    uint256 public constant FEE_AMOUNT_UPPER_BOUND = 1e25;
    uint256 public constant EXTENSION_FEE_PER_DAY = 1e18;
    uint256 public constant EXTENSION_FEE_PER_DAY_LOWER_BOUND = 1e18;
    uint256 public constant EXTENSION_FEE_PER_DAY_UPPER_BOUND = 1e23;

    modifier initialized() {
        IFarmRegistry(registry).initialize(FARM_REGISTRY_OWNER, USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
        _;
    }

    modifier deployerRegistered() {
        IFarmRegistry(registry).registerFarmDeployer(owner);
        _;
    }

    function setUp() public override {
        super.setUp();
        registryImp = new FarmRegistry();
        upgradeUtil = new UpgradeUtil();
        registry = createRegistry();
    }

    function createRegistry() public useKnownActor(FARM_REGISTRY_OWNER) returns (address) {
        address registryProxy;
        registryImp = new FarmRegistry();
        upgradeUtil = new UpgradeUtil();
        registryProxy = upgradeUtil.deployErc1967Proxy(address(registryImp));
        return registryProxy;
    }
}

contract InitializeTest is FarmRegistryTest {
    function test_Initialize_RevertWhen_receiverIsZeroAddress() public useKnownActor(FARM_REGISTRY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).initialize(address(0), USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_Initialize_RevertWhen_tokenIsZeroAddress() public useKnownActor(FARM_REGISTRY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).initialize(FARM_REGISTRY_OWNER, address(0), FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_init(uint256 feeAmt, uint256 extensionFeePerDay) public useKnownActor(FARM_REGISTRY_OWNER) {
        address feeReceiver = FARM_REGISTRY_OWNER;
        address feeToken = USDS;
        feeAmt = bound(feeAmt, FEE_AMOUNT_LOWER_BOUND, FEE_AMOUNT_UPPER_BOUND);
        extensionFeePerDay =
            bound(extensionFeePerDay, EXTENSION_FEE_PER_DAY_LOWER_BOUND, EXTENSION_FEE_PER_DAY_UPPER_BOUND);

        address _feeReceiver;
        address _feeToken;
        uint256 _feeAmount;
        uint256 _extensionFeePerDay;
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FeeParamsUpdated(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        IFarmRegistry(registry).initialize(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        (_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay) =
            IFarmRegistry(registry).getFeeParams(makeAddr("RANDOM"));
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
        assertEq(_extensionFeePerDay, extensionFeePerDay);
        assertEq(OwnableUpgradeable(registry).owner(), currentActor);
        assertEq(IFarmRegistry(registry).feeReceiver(), feeReceiver);
        assertEq(IFarmRegistry(registry).feeToken(), feeToken);
        assertEq(IFarmRegistry(registry).feeAmount(), feeAmt);
        assertEq(IFarmRegistry(registry).extensionFeePerDay(), extensionFeePerDay);
    }
}

contract RegisterFarmTest is FarmRegistryTest {
    function test_RegisterFarm_RevertWhen_DeployerNotRegistered()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
    {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.DeployerNotRegistered.selector));
        IFarmRegistry(registry).registerFarm(actors[6], actors[4]);
    }

    function test_RevertWhen_InvalidAddress()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        address creator = actors[5];
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).registerFarm(address(0), creator);
    }

    function test_RevertWhen_FarmAlreadyRegistered()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        address farm = actors[6];
        address creator = actors[5];
        vm.startPrank(owner);

        IFarmRegistry(registry).registerFarm(farm, creator);
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.FarmAlreadyRegistered.selector));
        IFarmRegistry(registry).registerFarm(farm, creator);
    }

    function test_registerFarm() public useKnownActor(FARM_REGISTRY_OWNER) initialized deployerRegistered {
        address farm = actors[6];
        address creator = actors[5];

        vm.startPrank(owner);
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FarmRegistered(farm, creator, owner);
        IFarmRegistry(registry).registerFarm(farm, creator);
        assertEq(IFarmRegistry(registry).getFarmList()[0], farm);
    }
}

contract RegisterFarmDeployerTest is FarmRegistryTest {
    function test_RegisterFarmDeployer_RevertWhen_DeployerAddressIsZero()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
    {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).registerFarmDeployer(address(0));
    }

    function test_RegisterFarmDeployer_RevertWhen_DeployerIsAlreadyRegistered()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.DeployerAlreadyRegistered.selector));
        IFarmRegistry(registry).registerFarmDeployer(owner);
    }

    function test_registerFarmDeployer() public useKnownActor(FARM_REGISTRY_OWNER) initialized {
        address deployer = actors[5];
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FarmDeployerUpdated(deployer, true);
        IFarmRegistry(registry).registerFarmDeployer(deployer);
        assertEq(IFarmRegistry(registry).getFarmDeployerList()[0], deployer);
        assertEq(IFarmRegistry(registry).deployerRegistered(deployer), true);
    }
}

contract RemoveFarmDeployerTest is FarmRegistryTest {
    function test_RemoveFarmDeployer_RevertWhen_invalidDeployerId()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        uint16 deployerId = uint16(IFarmRegistry(registry).getFarmDeployerList().length);
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidDeployerId.selector));
        IFarmRegistry(registry).removeDeployer(deployerId);
    }

    function test_removeLastDeployer() public useKnownActor(FARM_REGISTRY_OWNER) initialized deployerRegistered {
        IFarmRegistry(registry).registerFarmDeployer(actors[10]);
        IFarmRegistry(registry).registerFarmDeployer(actors[11]);
        uint16 deployerId = uint16(IFarmRegistry(registry).getFarmDeployerList().length - 1);
        uint16 lengthBfr = uint16(IFarmRegistry(registry).getFarmDeployerList().length);
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FarmDeployerUpdated(actors[11], false);
        IFarmRegistry(registry).removeDeployer(deployerId);
        assertEq(IFarmRegistry(registry).getFarmDeployerList()[0], owner);
        assertEq(IFarmRegistry(registry).getFarmDeployerList()[1], actors[10]);
        assertEq(uint16(IFarmRegistry(registry).getFarmDeployerList().length), lengthBfr - 1); //check length after poping a deployer
    }

    function test_removeMiddleDeployer() public useKnownActor(FARM_REGISTRY_OWNER) initialized deployerRegistered {
        IFarmRegistry(registry).registerFarmDeployer(actors[10]);
        IFarmRegistry(registry).registerFarmDeployer(actors[11]);
        uint16 deployerId = uint16(IFarmRegistry(registry).getFarmDeployerList().length - 2);
        uint16 lengthBfr = uint16(IFarmRegistry(registry).getFarmDeployerList().length);
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FarmDeployerUpdated(actors[10], false);
        IFarmRegistry(registry).removeDeployer(deployerId);
        assertEq(IFarmRegistry(registry).getFarmDeployerList()[0], owner);
        assertEq(IFarmRegistry(registry).getFarmDeployerList()[1], actors[11]);
        assertEq(uint16(IFarmRegistry(registry).getFarmDeployerList().length), lengthBfr - 1); //check length after poping a deployer
    }
}

contract UpdatePrivilegeTest is FarmRegistryTest {
    function test_UpdatePrivilege_RevertWhen_PrivilegeSameAsDesired()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.PrivilegeSameAsDesired.selector));
        IFarmRegistry(registry).updatePrivilege(owner, false);
    }

    function test_UpdatePrivilege_RevertWhen_callerIsNotOwner()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        IFarmRegistry(registry).updatePrivilege(owner, false);
    }

    function test_updatePrivilege() public useKnownActor(FARM_REGISTRY_OWNER) initialized deployerRegistered {
        vm.expectEmit(address(registry));
        emit IFarmRegistry.PrivilegeUpdated(owner, true);
        IFarmRegistry(registry).updatePrivilege(owner, true);
        assertEq(IFarmRegistry(registry).isPrivilegedUser(owner), true);

        // Test getFeeParams
        (address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay) =
            IFarmRegistry(registry).getFeeParams(owner);
        assertEq(_feeReceiver, FARM_REGISTRY_OWNER);
        assertEq(_feeToken, USDS);
        assertEq(_feeAmount, 0);
        assertEq(_extensionFeePerDay, 0);
    }
}

contract UpdateFeeParamsTest is FarmRegistryTest {
    function test_UpdateFeeParams_RevertWhen_callerIsNotOwner()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        IFarmRegistry(registry).updateFeeParams(owner, USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_UpdateFeeParams_RevertWhen_InvalidAddress()
        public
        useKnownActor(FARM_REGISTRY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).updateFeeParams(address(0), USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
        vm.expectRevert(abi.encodeWithSelector(IFarmRegistry.InvalidAddress.selector));
        IFarmRegistry(registry).updateFeeParams(owner, address(0), FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_updateFeeParams() public useKnownActor(FARM_REGISTRY_OWNER) initialized deployerRegistered {
        address feeReceiver = actors[5];
        address feeToken = actors[6];
        uint256 feeAmt = FEE_AMOUNT;
        uint256 extensionFeePerDay = EXTENSION_FEE_PER_DAY;
        vm.expectEmit(address(registry));
        emit IFarmRegistry.FeeParamsUpdated(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        IFarmRegistry(registry).updateFeeParams(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        // Test getFeeParams
        (address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay) =
            IFarmRegistry(registry).getFeeParams(makeAddr("RANDOM"));
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
        assertEq(_extensionFeePerDay, extensionFeePerDay);
        assertEq(OwnableUpgradeable(registry).owner(), currentActor);
        assertEq(IFarmRegistry(registry).feeReceiver(), feeReceiver);
        assertEq(IFarmRegistry(registry).feeToken(), feeToken);
        assertEq(IFarmRegistry(registry).feeAmount(), feeAmt);
        assertEq(IFarmRegistry(registry).extensionFeePerDay(), extensionFeePerDay);
    }
}
