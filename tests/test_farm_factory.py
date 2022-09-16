from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    UniswapFarmV1Deployer,
    reverts,
    ZERO_ADDRESS
)
import pytest
import eth_utils
from conftest import (
    GAS_LIMIT,
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
        token_obj('usds'),
        500e18,
        {'from': deployer}
    )
    return factory_contract


@pytest.fixture(scope='module')
def farm_deployer(factory):
    farm_deployer = UniswapFarmV1Deployer.deploy(factory, {'from': deployer})
    factory.registerFarmDeployer(
        'UniswapFarmV1Deployer',
        farm_deployer,
        {'from': deployer}
    )
    return farm_deployer


@pytest.mark.skip()
class TestMain:
    def test_main(self, farm_deployer):
        pass


# @pytest.mark.skip()
class TestInitialization:
    def test_initialization_invalid_address(self, factory_contract):
        print('-------------------------------------------------')
        print('Trying to initialize with feeToken as invalid address')
        with reverts('Invalid address'):
            factory_contract.initialize(
                ZERO_ADDRESS,
                500e18,
                {'from': deployer}
            )
        print('Transaction reverted with: Invalid address')
        print('-------------------------------------------------')

    def test_initialization_zero_fees(self, factory_contract):
        print('-------------------------------------------------')
        print('Trying to initialize with feeAmount as 0')
        with reverts('Fee cannot be zero'):
            factory_contract.initialize(
                token_obj('usds'),
                0,
                {'from': deployer}
            )
        print('Transaction reverted with: Fee cannot be zero')
        print('-------------------------------------------------')

    def test_initialization(self, factory):
        print('-------------------------------------------------')
        print('Testing proper initialization')
        assert factory.feeToken() == token_obj('usds')
        assert factory.feeAmount() == 500e18
        receiver = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'
        assert factory.FEE_RECEIVER() == receiver


# @pytest.mark.skip()
class TestRegisterFarmDeployer:
    def test_only_admin(self, factory):
        with reverts('Ownable: caller is not the owner'):
            factory.registerFarmDeployer(
                'AaveFarm',
                accounts[1],
                {'from': accounts[1]}
            )

    def test_zero_address(self, factory):
        with reverts('Invalid address'):
            factory.registerFarmDeployer(
                'AaveFarm',
                ZERO_ADDRESS,
                {'from': accounts[0]}
            )

    def test_registerFarmDeployer(self, factory, farm_deployer):
        factory.registerFarmDeployer(
            'AaveFarm',
            accounts[1],
            {'from': accounts[0]}
        )

    def test_register_multiple_deployers(self, factory, farm_deployer):
        with reverts('Deployer already exists'):
            factory.registerFarmDeployer(
                'UniswapFarmV1Deployer',
                accounts[1],
                {'from': accounts[0]}
            )
