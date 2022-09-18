from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    UniswapFarmV1Deployer,
    reverts,
    ZERO_ADDRESS,
    UniswapFarmV1
)
import pytest
import eth_utils
from conftest import (
    GAS_LIMIT,
    fund_account,
    token_obj
)


@pytest.fixture(scope='module', autouse=True)
def setUp():
    global deployer
    deployer = accounts[0]


@pytest.fixture(scope='module')
def factory_contract():
    factory_impl = FarmFactory.deploy(
        {'from': deployer}
    )
    proxy = TransparentUpgradeableProxy.deploy(
        factory_impl.address,
        '0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25',
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    factory_contract = Contract.from_abi(
        'FarmFactory',
        proxy.address,
        FarmFactory.abi
    )

    return factory_contract


@pytest.fixture(scope='module')
def factory(factory_contract):
    factory_contract.initialize(
        deployer,
        token_obj('usds'),
        500e18,
        {'from': deployer}
    )
    return factory_contract


@pytest.fixture(scope='module')
def farm_deployer(factory):
    farm_deployer = UniswapFarmV1Deployer.deploy(factory, {'from': deployer})
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )
    return farm_deployer


@pytest.fixture(scope='module')
def farm():
    farm = UniswapFarmV1.deploy({'from': deployer})
    return farm


class TestInitialization:
    def test_initialization_invalid_token(self, factory_contract):
        print('-------------------------------------------------')
        print('Trying to initialize with feeToken as invalid address')
        with reverts('Invalid address'):
            factory_contract.initialize(
                deployer,
                ZERO_ADDRESS,
                500e18,
                {'from': deployer}
            )
        print('Transaction reverted with: Invalid address')
        print('-------------------------------------------------')

    def test_initialization_invalid_receiver(self, factory_contract):
        print('-------------------------------------------------')
        print('Trying to initialize with feeToken as invalid address')
        with reverts('Invalid address'):
            factory_contract.initialize(
                ZERO_ADDRESS,
                token_obj('usds'),
                500e18,
                {'from': deployer}
            )
        print('Transaction reverted with: Invalid address')
        print('-------------------------------------------------')

    def test_initialization_zero_fees(self, factory_contract):
        print('-------------------------------------------------')
        print('Trying to initialize with feeAmount as 0')
        with reverts('Fee can not be 0'):
            factory_contract.initialize(
                deployer,
                token_obj('usds'),
                0,
                {'from': deployer}
            )
        print('Transaction reverted with: Fee can not be 0')
        print('-------------------------------------------------')

    def test_initialization(self, factory):
        print('-------------------------------------------------')
        print('Testing proper initialization')
        assert factory.feeToken() == token_obj('usds')
        assert factory.feeAmount() == 500e18
        assert factory.feeReceiver() == deployer


class TestRegisterFarmDeployer:
    def test_only_admin(self, factory):
        with reverts('Ownable: caller is not the owner'):
            factory.registerFarmDeployer(
                accounts[1],
                {'from': accounts[1]}
            )

    def test_zero_address(self, factory):
        with reverts('Invalid address'):
            factory.registerFarmDeployer(
                ZERO_ADDRESS,
                {'from': deployer}
            )

    def test_registerFarmDeployer(self, factory):
        tx = factory.registerFarmDeployer(
            accounts[1],
            {'from': deployer}
        )
        event = tx.events['FarmDeployerRegistered']
        assert event['deployer'] == accounts[1]
        assert factory.deployerRegistered(accounts[1])

    def test_registerFarmDeployer_multiple(self, factory):
        for i in range(2, 9):
            tx = factory.registerFarmDeployer(
                accounts[i],
                {'from': deployer}
            )
            event = tx.events['FarmDeployerRegistered']
            assert event['deployer'] == accounts[i]
            assert factory.deployerRegistered(accounts[i])

    def test_register_same_deployer_twice(self, factory):
        factory.registerFarmDeployer(
            accounts[1],
            {'from': deployer}
        )
        with reverts('Deployer already registered'):
            factory.registerFarmDeployer(
                accounts[1],
                {'from': deployer}
            )


class TestRemoveDeployer:
    def test_only_admin(self, factory):
        with reverts('Ownable: caller is not the owner'):
            factory.removeDeployer(
                0,
                {'from': accounts[1]}
            )

    def test_invalid_deployer_id(self, factory):
        factory.registerFarmDeployer(
            accounts[1],
            {'from': deployer}
        )
        with reverts('Invalid deployer id'):
            factory.removeDeployer(
                1,
                {'from': deployer}
            )

    def test_removeDeployer(self, factory):
        for i in range(1, 5):
            factory.registerFarmDeployer(
                accounts[i],
                {'from': deployer}
            )
        tx = factory.removeDeployer(
            0,
            {'from': deployer}
        )
        event = tx.events['FarmDeployerRemoved']
        assert event['deployer'] == accounts[1]
        assert factory.deployerList(0) == accounts[4]
        for i in range(2):
            assert factory.deployerList(i+1) == accounts[i+2]


class TestRegisterFarm:
    def test_unregisteredDeployer(self, factory, farm):
        with reverts('Deployer not registered'):
            factory.registerFarm(
                farm,
                accounts[5],
                True,
                {'from': accounts[5]}
            )

    def test_registerFarm_no_fees(self, factory, farm):
        factory.registerFarmDeployer(
            accounts[1],
            {'from': deployer}
        )
        tx = factory.registerFarm(
            farm,
            accounts[1],
            False,
            {'from': accounts[1]}
        )
        event = tx.events['FarmRegistered']
        assert farm == event['farm']
        assert accounts[1] == event['creator']
        assert factory.farms(0) == farm
        assert factory.farmRegistered(farm)

    def test_registerFarm_with_fees(self, factory, farm):
        fund_account(accounts[2], 'usds', 500*1e18)
        token_obj('usds').approve(
            factory,
            500*1e18,
            {'from': accounts[2]}
        )
        factory.registerFarmDeployer(
            accounts[2],
            {'from': deployer}
        )
        tx = factory.registerFarm(
            farm,
            accounts[2],
            True,
            {'from': accounts[2]}
        )
        event = tx.events['FarmRegistered']
        assert farm == event['farm']
        assert accounts[2] == event['creator']
        assert factory.farms(0) == farm
        assert factory.farmRegistered(farm)


class TestUpdateFeeParams:
    def test_updateFeeParams(self, factory):
        tx = factory.updateFeeParams(
            accounts[3],
            token_obj('usdc'),
            100*1e18,
            {'from': deployer}
        )
        event = tx.events['FeeParamsUpdated']
        assert event['receiver'] == accounts[3]
        assert event['token'] == token_obj('usdc')
        assert event['amount'] == 100*1e18
        assert factory.feeReceiver() == accounts[3]
        assert factory.feeToken() == token_obj('usdc')
        assert factory.feeAmount() == 100*1e18
