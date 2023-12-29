// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarm, RewardTokenData} from "../contracts/BaseFarm.sol";
import {BaseE20Farm} from "../contracts/e20-farms/BaseE20Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {FarmFactory} from "../contracts/FarmFactory.sol";
import {BaseFarmDeployer} from "../contracts/BaseFarmDeployer.sol";
import {UpgradeUtil} from "../test/utils/UpgradeUtil.t.sol";

abstract contract FarmFactoryTest is TestNetworkConfig {
    UpgradeUtil internal upgradeUtil;
    FarmFactory public factoryImp;

    event FarmRegistered(address indexed farm, address indexed creator, address indexed deployer);
    event FarmDeployerUpdated(address deployer, bool registered);
    event FeeParamsUpdated(address receiver, address token, uint256 amount, uint256 extensionFeePerDay);
    event PrivilegeUpdated(address deployer, bool privilege);

    modifier initialized() {
        FarmFactory(factory).initialize(FACTORY_OWNER, USDS, 1e20, 1e18);
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
    function test_revertsWhen_receiverIsZeroAddress() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).initialize(address(0), USDS, 1e20, 1e18);
    }

    function test_revertsWhen_tokenIsZeroAddress() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).initialize(FACTORY_OWNER, address(0), 1e20, 1e18);
    }

    function test_init(uint256 feeAmt, uint256 extensionFeePerDay) public useKnownActor(FACTORY_OWNER) {
        address feeReceiver = FACTORY_OWNER;
        address feeToken = USDS;
        feeAmt = bound(feeAmt, 1e18, 1e25);
        extensionFeePerDay = bound(extensionFeePerDay, 1e18, 1e23);

        address _feeReceiver;
        address _feeToken;
        uint256 _feeAmount;
        uint256 _extensionFeePerDay;
        vm.expectEmit(true, true, true, true);
        emit FeeParamsUpdated(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        FarmFactory(factory).initialize(feeReceiver, feeToken, feeAmt, extensionFeePerDay);
        (_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay) =
            FarmFactory(factory).getFeeParams(makeAddr("RANDOM"));
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
        assertEq(_extensionFeePerDay, extensionFeePerDay);
        assertEq(FarmFactory(factory).owner(), currentActor);
    }
}

contract RegisterFarmTest is FarmFactoryTest {
    function test_revertsWhen_DeployerNotRegistered() public useKnownActor(FACTORY_OWNER) initialized {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.DeployerNotRegistered.selector));
        FarmFactory(factory).registerFarm(actors[6], actors[4]);
    }

    function test_registerFarm() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        address farm = actors[6];
        address creator = actors[5];

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit FarmRegistered(farm, creator, owner);
        FarmFactory(factory).registerFarm(farm, creator);
        assertEq(FarmFactory(factory).getFarmList()[0], farm);
    }
}

contract RegisterFarmDeployerTest is FarmFactoryTest {
    function test_revertsWhen_DeployerAddressIsZero() public useKnownActor(FACTORY_OWNER) initialized {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).registerFarmDeployer(address(0));
    }

    function test_revertsWhen_DeployerIsAlreadyRegistered()
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
        vm.expectEmit(true, true, false, false);
        emit FarmDeployerUpdated(deployer, true);
        FarmFactory(factory).registerFarmDeployer(deployer);
        assertEq(FarmFactory(factory).getFarmDeployerList()[0], deployer);
        assertEq(FarmFactory(factory).deployerRegistered(deployer), true);
    }
}

contract RemoveFarmDeployerTest is FarmFactoryTest {
    function test_revertsWhen_invalidDeployerId() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        uint16 deployerId = uint16(FarmFactory(factory).getFarmDeployerList().length);
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidDeployerId.selector));
        FarmFactory(factory).removeDeployer(deployerId);
    }

    function test_removeLastDeployer() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        FarmFactory(factory).registerFarmDeployer(actors[10]);
        FarmFactory(factory).registerFarmDeployer(actors[11]);
        uint16 deployerId = uint16(FarmFactory(factory).getFarmDeployerList().length - 1);
        uint16 lengthBfr = uint16(FarmFactory(factory).getFarmDeployerList().length);
        vm.expectEmit(true, true, false, false);
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
        vm.expectEmit(true, true, false, false);
        emit FarmDeployerUpdated(actors[10], false);
        FarmFactory(factory).removeDeployer(deployerId);
        assertEq(FarmFactory(factory).getFarmDeployerList()[0], owner);
        assertEq(FarmFactory(factory).getFarmDeployerList()[1], actors[11]);
        assertEq(uint16(FarmFactory(factory).getFarmDeployerList().length), lengthBfr - 1); //check length after poping a deployer
    }
}

contract UpdatePrivilegeTest is FarmFactoryTest {
    function test_revertsWhen_PrivilegeSameAsDesired()
        public
        useKnownActor(FACTORY_OWNER)
        initialized
        deployerRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.PrivilegeSameAsDesired.selector));
        FarmFactory(factory).updatePrivilege(owner, false);
    }

    function test_revertsWhen_callerIsNotOwner() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        vm.startPrank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        FarmFactory(factory).updatePrivilege(owner, false);
    }

    function test_updatePrivilege() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        vm.expectEmit(true, true, false, false);
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
    function test_revertsWhen_callerIsNotOwner() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        vm.startPrank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        FarmFactory(factory).updateFeeParams(owner, USDS, 1e20, 1e18);
    }

    function test_updateFeeParams() public useKnownActor(FACTORY_OWNER) initialized deployerRegistered {
        address feeReceiver = actors[5];
        address feeToken = actors[6];
        uint256 feeAmt = 1e20;
        uint256 extensionFeePerDay = 1e18;
        vm.expectEmit(false, false, false, true);
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
