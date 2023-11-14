// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseFarm, RewardTokenData} from "../contracts/BaseFarm.sol";
import {BaseE20Farm} from "../contracts/e20-farms/BaseE20Farm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TestNetworkConfig} from "./utils/TestNetworkConfig.t.sol";
import {FarmFactory} from "../contracts/FarmFactory.sol";
import {BaseFarmDeployer} from "../contracts/BaseFarmDeployer.sol";
import {UpgradeUtil} from "../test/utils/UpgradeUtil.t.sol";
import {console} from "forge-std/console.sol";

abstract contract FarmFactoryTest is TestNetworkConfig {
    UpgradeUtil internal upgradeUtil;
    FarmFactory public factoryImp;

    event FarmRegistered(address indexed farm, address indexed creator, address indexed deployer);
    event FarmDeployerRegistered(address deployer);
    event FarmDeployerRemoved(address deployer);
    event FeeParamsUpdated(address receiver, address token, uint256 amount);
    event PrivilegeUpdated(address deployer, bool privilege);

    modifier initialized() {
        FarmFactory(factory).initialize(FACTORY_OWNER, USDS, 1e20);
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
        FarmFactory(factory).initialize(address(0), USDS, 1e20);
    }

    function test_revertsWhen_tokenIsZeroAddress() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.InvalidAddress.selector));
        FarmFactory(factory).initialize(FACTORY_OWNER, address(0), 1e20);
    }

    function test_revertsWhen_feeAmountIsZero() public useKnownActor(FACTORY_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FarmFactory.FeeCannotBeZero.selector));
        FarmFactory(factory).initialize(FACTORY_OWNER, USDS, 0);
    }

    function test_init(uint256 feeAmt) public useKnownActor(FACTORY_OWNER) {
        address feeReceiver = FACTORY_OWNER;
        address feeToken = USDS;
        feeAmt = bound(feeAmt, 1e18, 1e25);

        address _feeReceiver;
        address _feeToken;
        uint256 _feeAmount;
        vm.expectEmit(true, true, true, false);
        emit FeeParamsUpdated(feeReceiver, feeToken, feeAmt);
        FarmFactory(factory).initialize(feeReceiver, feeToken, feeAmt);
        (_feeReceiver, _feeToken, _feeAmount) = FarmFactory(factory).getFeeParams();
        assertEq(_feeReceiver, feeReceiver);
        assertEq(_feeToken, feeToken);
        assertEq(_feeAmount, feeAmt);
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
        vm.expectEmit(true, true, false, true);
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
        emit FarmDeployerRegistered(deployer);
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
        emit FarmDeployerRemoved(actors[11]);
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
        emit FarmDeployerRemoved(actors[10]);
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
    }
}
