// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Farm, RewardTokenData} from "../contracts/Farm.sol";
import {E20Farm} from "../contracts/e20-farms/E20Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {FarmFactory} from "../contracts/FarmFactory.sol";
import {FarmDeployer} from "../contracts/FarmDeployer.sol";
import {UpgradeUtil} from "../test/utils/UpgradeUtil.t.sol";

abstract contract FarmFactoryTest is TestNetworkConfig {
    UpgradeUtil internal upgradeUtil;
    FarmFactory public factoryImp;
    uint256 public constant FEE_AMOUNT = 1e20;
    uint256 public constant FEE_AMOUNT_LOWER_BOUND = 1e18;
    uint256 public constant FEE_AMOUNT_UPPER_BOUND = 1e25;
    uint256 public constant EXTENSION_FEE_PER_DAY = 1e18;
    uint256 public constant EXTENSION_FEE_PER_DAY_LOWER_BOUND = 1e18;
    uint256 public constant EXTENSION_FEE_PER_DAY_UPPER_BOUND = 1e23;

    event FarmRegistered(address indexed farm, address indexed creator, address indexed deployer);
    event FarmDeployerUpdated(address deployer, bool registered);
    event FeeParamsUpdated(address receiver, address token, uint256 amount, uint256 extensionFeePerDay);
    event PrivilegeUpdated(address deployer, bool privilege);

    modifier initialized() {
        FarmFactory(factory).initialize(FACTORY_OWNER, USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
        _;
    }

    modifier deployerRegistered() {
        FarmFactory(factory).registerFarmDeployer(owner);
        _;
    }

    function setUp() public override {
        super.setUp();
        factoryImp = new FarmFactory();
        upgradeUtil = new UpgradeUtil();
        factory = createFactory();
    }

    function createFactory() public useKnownActor(FACTORY_OWNER) returns (address) {
        address factoryProxy;
        factoryImp = new FarmFactory();
        upgradeUtil = new UpgradeUtil();
        factoryProxy = upgradeUtil.deployErc1967Proxy(address(factoryImp));
        return factoryProxy;
    }
}

contract InitializeTest is FarmFactoryTest {
    function test_Initialize_RevertWhen_receiverIsZeroAddress() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).initialize(address(0), USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_Initialize_RevertWhen_tokenIsZeroAddress() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).initialize(FACTORY_OWNER, address(0), FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_init(uint256 feeAmt, uint256 extensionFeePerDay) public useKnownActor(FACTORY_OWNER) {
        address feeReceiver = FACTORY_OWNER;
        address feeToken = USDS;
        feeAmt = bound(feeAmt, FEE_AMOUNT_LOWER_BOUND, FEE_AMOUNT_UPPER_BOUND);
        extensionFeePerDay =
            bound(extensionFeePerDay, EXTENSION_FEE_PER_DAY_LOWER_BOUND, EXTENSION_FEE_PER_DAY_UPPER_BOUND);

        address _feeReceiver;
        address _feeToken;
        uint256 _feeAmount;
        uint256 _extensionFeePerDay;
        vm.expectEmit(address(factory));
        emit FeeParamsUpdated(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        FarmFactory(factory).initialize(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        (_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay) =
            FarmFactory(factory).getFeeParams(makeAddr("RANDOM"));
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
        assertEq(_extensionFeePerDay, extensionFeePerDay);
        assertEq(FarmFactory(factory).owner(), currentActor);
        assertEq(FarmFactory(factory).feeReceiver(), feeReceiver);
        assertEq(FarmFactory(factory).feeToken(), feeToken);
        assertEq(FarmFactory(factory).feeAmount(), feeAmt);
        assertEq(FarmFactory(factory).extensionFeePerDay(), extensionFeePerDay);
    }
}

contract RegisterFarmTest is FarmFactoryTest {
    function test_RegisterFarm_RevertWhen_DeployerNotRegistered() public useKnownActor(FACTORY_OWNER) initialized {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.DeployerNotRegistered.selector));
        FarmFactory(factory).registerFarm(actors[6], actors[4]);
    }

    function test_registerFarm() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        address farm = actors[6];
        address creator = actors[5];

        vm.startPrank(owner);
        vm.expectEmit(address(factory));
        emit FarmRegistered(farm, creator, owner);
        FarmFactory(factory).registerFarm(farm, creator);
        assertEq(FarmFactory(factory).getFarmList()[0], farm);
    }
}

contract RegisterFarmDeployerTest is FarmFactoryTest {
    function test_RegisterFarmDeployer_RevertWhen_DeployerAddressIsZero()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
    {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).registerFarmDeployer(address(0));
    }

    function test_RegisterFarmDeployer_RevertWhen_DeployerIsAlreadyRegistered()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.DeployerAlreadyRegistered.selector));
        FarmFactory(factory).registerFarmDeployer(owner);
    }

    function test_registerFarmDeployer() public useKnownActor(FACTORY_OWNER) initialized {
        address deployer = actors[5];
        vm.expectEmit(address(factory));
        emit FarmDeployerUpdated(deployer, true);
        FarmFactory(factory).registerFarmDeployer(deployer);
        assertEq(FarmFactory(factory).getFarmDeployerList()[0], deployer);
        assertEq(FarmFactory(factory).deployerRegistered(deployer), true);
    }
}

contract RemoveFarmDeployerTest is FarmFactoryTest {
    function test_RemoveFarmDeployer_RevertWhen_invalidDeployerId()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        uint16 deployerId = uint16(FarmFactory(factory).getFarmDeployerList().length);
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidDeployerId.selector));
        FarmFactory(factory).removeDeployer(deployerId);
    }

    function test_removeLastDeployer() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        FarmFactory(factory).registerFarmDeployer(actors[10]);
        FarmFactory(factory).registerFarmDeployer(actors[11]);
        uint16 deployerId = uint16(FarmFactory(factory).getFarmDeployerList().length - 1);
        uint16 lengthBfr = uint16(FarmFactory(factory).getFarmDeployerList().length);
        vm.expectEmit(address(factory));
        emit FarmDeployerUpdated(actors[11], false);
        FarmFactory(factory).removeDeployer(deployerId);
        assertEq(FarmFactory(factory).getFarmDeployerList()[0], owner);
        assertEq(FarmFactory(factory).getFarmDeployerList()[1], actors[10]);
        assertEq(uint16(FarmFactory(factory).getFarmDeployerList().length), lengthBfr - 1); //check length after poping a deployer
    }

    function test_removeMiddleDeployer() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        FarmFactory(factory).registerFarmDeployer(actors[10]);
        FarmFactory(factory).registerFarmDeployer(actors[11]);
        uint16 deployerId = uint16(FarmFactory(factory).getFarmDeployerList().length - 2);
        uint16 lengthBfr = uint16(FarmFactory(factory).getFarmDeployerList().length);
        vm.expectEmit(address(factory));
        emit FarmDeployerUpdated(actors[10], false);
        FarmFactory(factory).removeDeployer(deployerId);
        assertEq(FarmFactory(factory).getFarmDeployerList()[0], owner);
        assertEq(FarmFactory(factory).getFarmDeployerList()[1], actors[11]);
        assertEq(uint16(FarmFactory(factory).getFarmDeployerList().length), lengthBfr - 1); //check length after poping a deployer
    }
}

contract UpdatePrivilegeTest is FarmFactoryTest {
    function test_UpdatePrivilege_RevertWhen_PrivilegeSameAsDesired()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.PrivilegeSameAsDesired.selector));
        FarmFactory(factory).updatePrivilege(owner, false);
    }

    function test_UpdatePrivilege_RevertWhen_callerIsNotOwner()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.startPrank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        FarmFactory(factory).updatePrivilege(owner, false);
    }

    function test_updatePrivilege() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        vm.expectEmit(address(factory));
        emit PrivilegeUpdated(owner, true);
        FarmFactory(factory).updatePrivilege(owner, true);
        assertEq(FarmFactory(factory).isPrivilegedDeployer(owner), true);

        // Test getFeeParams
        (address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay) =
            FarmFactory(factory).getFeeParams(owner);
        assertEq(_feeReceiver, FACTORY_OWNER);
        assertEq(_feeToken, USDS);
        assertEq(_feeAmount, 0);
        assertEq(_extensionFeePerDay, 0);
    }
}

contract UpdateFeeParamsTest is FarmFactoryTest {
    function test_UpdateFeeParams_RevertWhen_callerIsNotOwner()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.startPrank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        FarmFactory(factory).updateFeeParams(owner, USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_UpdateFeeParams_RevertWhen_InvalidAddress()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).updateFeeParams(address(0), USDS, FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).updateFeeParams(owner, address(0), FEE_AMOUNT, EXTENSION_FEE_PER_DAY);
    }

    function test_updateFeeParams() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        address feeReceiver = actors[5];
        address feeToken = actors[6];
        uint256 feeAmt = FEE_AMOUNT;
        uint256 extensionFeePerDay = EXTENSION_FEE_PER_DAY;
        vm.expectEmit(address(factory));
        emit FeeParamsUpdated(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        FarmFactory(factory).updateFeeParams(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        // Test getFeeParams
        (address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay) =
            FarmFactory(factory).getFeeParams(makeAddr("RANDOM"));
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
        assertEq(_extensionFeePerDay, extensionFeePerDay);
        assertEq(FarmFactory(factory).owner(), currentActor);
        assertEq(FarmFactory(factory).feeReceiver(), feeReceiver);
        assertEq(FarmFactory(factory).feeToken(), feeToken);
        assertEq(FarmFactory(factory).feeAmount(), feeAmt);
        assertEq(FarmFactory(factory).extensionFeePerDay(), extensionFeePerDay);
    }
}
