from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    UniswapFarmV1Deployer,
    reverts,
    ZERO_ADDRESS,
    UniswapFarmV1,
    chain
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
    with reverts('Invalid address'):
        farm_deployer = UniswapFarmV1Deployer.deploy(
            ZERO_ADDRESS,
            {'from': deployer}
        )
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


# @pytest.mark.skip()
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


# @pytest.mark.skip()
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


# @pytest.mark.skip()
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


# @pytest.mark.skip()
class TestRegisterFarm:
    def test_unregisteredDeployer(self, factory, farm):
        with reverts('Deployer not registered'):
            factory.registerFarm(
                farm,
                accounts[5],
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
            {'from': accounts[2]}
        )
        event = tx.events['FarmRegistered']
        assert farm == event['farm']
        assert accounts[2] == event['creator']
        assert factory.farms(0) == farm
        assert factory.farmRegistered(farm)


# @pytest.mark.skip()
class TestUpdateFeeParams:
    def test_only_admin(self, factory):
        with reverts('Ownable: caller is not the owner'):
            factory.updateFeeParams(
                accounts[3],
                token_obj('usdc'),
                100*1e18,
                {'from': accounts[3]}
            )

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


# @pytest.mark.skip()
class TestDeployerInitialization:
    def test_deployer_initialization(self, farm_deployer, factory):
        print('Checking if deployer is initialized properly')
        assert farm_deployer.DEPLOYER_NAME() == 'UniswapV3FarmDeployer'
        assert farm_deployer.SPA() == token_obj('spa')
        assert farm_deployer.USDs() == token_obj('usds')
        assert farm_deployer.factory() == factory


# @pytest.mark.skip()
class TestUpdatePrivilege:
    def checkEventData(self, event, account, bool):
        assert event['deployer'] == account
        assert event['privilege'] == bool

    def test_updatePrivilege_onlyAdmin(self, farm_deployer):
        with reverts('Ownable: caller is not the owner'):
            farm_deployer.updatePrivilege(
                accounts[1],
                True,
                {'from': accounts[5]}
            )

    def test_addPrivilege(self, farm_deployer):
        tx = farm_deployer.updatePrivilege(
            accounts[1],
            True,
            {'from': deployer}
        )
        assert farm_deployer.isPrivilegedDeployer(accounts[1])
        self.checkEventData(tx.events['PrivilegeUpdated'], accounts[1], True)

    def test_removePrivilege(self, farm_deployer):
        farm_deployer.updatePrivilege(
            accounts[1],
            True,
            {'from': deployer}
        )
        tx = farm_deployer.updatePrivilege(
            accounts[1],
            False,
            {'from': deployer}
        )
        assert not farm_deployer.isPrivilegedDeployer(accounts[1])
        self.checkEventData(tx.events['PrivilegeUpdated'], accounts[1], False)

    def test_updateSamePrivilege_true(self, farm_deployer):
        farm_deployer.updatePrivilege(
            accounts[1],
            True,
            {'from': deployer}
        )
        with reverts('Privilege is same as desired'):
            farm_deployer.updatePrivilege(
                accounts[1],
                True,
                {'from': deployer}
            )

    def test_updateSamePrivilege_false(self, farm_deployer):
        farm_deployer.updatePrivilege(
            accounts[1],
            True,
            {'from': deployer}
        )
        farm_deployer.updatePrivilege(
            accounts[1],
            False,
            {'from': deployer}
        )
        with reverts('Privilege is same as desired'):
            farm_deployer.updatePrivilege(
                accounts[1],
                False,
                {'from': deployer}
            )

    def test_updatePrivilege_noPrivilege(self, farm_deployer):
        with reverts('Privilege is same as desired'):
            farm_deployer.updatePrivilege(
                accounts[1],
                False,
                {'from': deployer}
            )

    def test_updatePrivilege_multiple(self, farm_deployer):
        for i in range(0, 10):
            if (i % 2 == 0):
                farm_deployer.updatePrivilege(
                    accounts[i],
                    True,
                    {'from': deployer}
                )
                assert farm_deployer.isPrivilegedDeployer(accounts[i])


# @pytest.mark.skip()
class TestCreateFarm:
    @pytest.fixture(scope='module')
    def config(self):
        config = {
            'farm_admin': deployer,
            'farm_start_time': chain.time(),
            'cooldown_period': 0,
            'uniswap_pool_data': {
                'tokenA': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                'tokenB': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'tick_lower': -48960,
                'tick_upper': -6900,
            },
            'reward_token_data': [
                {
                    'token_addr': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                    'token_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1'  # noqa
                }
            ]
        }
        return config

    def test_create_farm_with_usds(self, farm_deployer, config, factory):
        print('Creating farm with token B as USDs')
        fund_account(deployer, 'usds', 1e20)
        token_obj('usds').approve(farm_deployer, 1e20, {'from': deployer})
        config['farm_start_time'] = chain.time()
        create_tx = farm_deployer.createFarm(
            (
                config['farm_admin'],
                config['farm_start_time'],
                config['cooldown_period'],
                list(config['uniswap_pool_data'].values()),
                list(
                    map(
                        lambda x: list(x.values()),
                        config['reward_token_data']
                    )
                ),
            ),
            {'from': deployer}
        )
        print('Checking whether farm is deployed correctly or not')
        farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
        event = create_tx.events['FeeCollected']
        assert event['claimable']
        assert event['creator'] == deployer
        assert event['token'] == token_obj('usds')
        assert event['amount'] == 1e20
        assert event['token'] == token_obj('usds')
        event = create_tx.events['FarmCreated']
        assert farm == event['farm']
        assert deployer == event['creator']
        print('Checking whether farm is added to factory or not')
        assert farm == factory.farms(0)
        assert factory.farmRegistered(farm)
        print('Checking whether farm is properly initialized or not')
        assert farm.lastFundUpdateTime() == config['farm_start_time']
        assert farm.farmStartTime() == config['farm_start_time']
        assert farm.owner() == deployer
        print('Everything looks good')

    def test_create_farm_with_spa(self, farm_deployer, config, factory):
        config['uniswap_pool_data']['tokenB'] = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'  # noqa
        config['uniswap_pool_data']['tokenA'] = '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'  # noqa
        config['uniswap_pool_data']['fee_tier'] = 10000
        config['uniswap_pool_data']['tick_lower'] = -322200
        config['uniswap_pool_data']['tick_upper'] = -318800
        fund_account(deployer, 'usds', 1e20)
        token_obj('usds').approve(farm_deployer, 1e20, {'from': deployer})
        print('Creating farm with token A as SPA')
        config['farm_start_time'] = chain.time()
        create_tx = farm_deployer.createFarm(
            (
                config['farm_admin'],
                config['farm_start_time'],
                config['cooldown_period'],
                list(config['uniswap_pool_data'].values()),
                list(
                    map(
                        lambda x: list(x.values()),
                        config['reward_token_data']
                    )
                ),
            ),
            {'from': deployer}
        )
        print('Checking whether farm is deployed correctly or not')
        farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
        event = create_tx.events['FeeCollected']
        assert event['claimable']
        assert event['creator'] == deployer
        assert event['token'] == token_obj('usds')
        assert event['amount'] == 1e20
        event = create_tx.events['FarmCreated']
        assert farm == event['farm']
        assert deployer == event['creator']
        print('Checking whether farm is added to factory or not')
        assert farm == factory.farms(0)
        assert factory.farmRegistered(farm)
        print('Checking whether farm is properly initialized or not')
        assert farm.lastFundUpdateTime() == config['farm_start_time']
        assert farm.farmStartTime() == config['farm_start_time']
        assert farm.owner() == deployer
        print('Everything looks good')

    def test_create_farm_with_spa_usds(self, farm_deployer, config, factory):
        config['uniswap_pool_data']['tokenB'] = '0xD74f5255D557944cf7Dd0E45FF521520002D5748'  # noqa
        config['uniswap_pool_data']['tokenA'] = '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'  # noqa
        fund_account(accounts[2], 'usds', 1e20)
        token_obj('usds').approve(farm_deployer, 1e20, {'from': accounts[2]})
        print('Creating farm for SPA/USDs')
        config['farm_start_time'] = chain.time()
        create_tx = farm_deployer.createFarm(
            (
                config['farm_admin'],
                config['farm_start_time'],
                config['cooldown_period'],
                list(config['uniswap_pool_data'].values()),
                list(
                    map(
                        lambda x: list(x.values()),
                        config['reward_token_data']
                    )
                ),
            ),
            {'from': accounts[2]}
        )
        print('Checking whether farm is deployed correctly or not')
        farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
        event = create_tx.events['FeeCollected']
        assert event['claimable']
        assert event['creator'] == accounts[2]
        assert event['token'] == token_obj('usds')
        assert event['amount'] == 1e20
        event = create_tx.events['FarmCreated']
        assert farm == event['farm']
        assert accounts[2] == event['creator']
        print('Checking whether farm is added to factory or not')
        assert farm == factory.farms(0)
        assert factory.farmRegistered(farm)
        print('Checking whether farm is properly initialized or not')
        assert farm.lastFundUpdateTime() == config['farm_start_time']
        assert farm.farmStartTime() == config['farm_start_time']
        assert farm.owner() == deployer
        print('Everything looks good')

    @pytest.mark.parametrize('creator', ['normal', 'privileged'])
    def test_create_farm_without_spa_usds(
        self, farm_deployer, config, factory, creator
    ):
        config['uniswap_pool_data']['tokenB'] = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'  # noqa
        config['uniswap_pool_data']['tokenA'] = '0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a'  # noqa
        config['farm_admin'] = accounts[4]
        if (creator == 'normal'):
            creator = accounts[3]
        if (creator == 'privileged'):
            creator = accounts[5]
        if (creator == accounts[3]):
            fund_account(creator, 'usds', 500*1e18)
            receiver = factory.feeReceiver()
            print('Fee receiver', receiver)
            balBefore = token_obj('usds').balanceOf(receiver)
            token_obj('usds').approve(
                farm_deployer,
                500*1e18,
                {'from': creator}
            )
        else:
            farm_deployer.updatePrivilege(
                creator,
                True,
                {'from': deployer}
            )
        print('Creating farm with ETH/GMX')
        config['farm_start_time'] = chain.time()
        create_tx = farm_deployer.createFarm(
            (
                config['farm_admin'],
                config['farm_start_time'],
                config['cooldown_period'],
                list(config['uniswap_pool_data'].values()),
                list(
                    map(
                        lambda x: list(x.values()),
                        config['reward_token_data']
                    )
                ),
            ),
            {'from': creator}
        )
        if (creator == accounts[3]):
            balAfter = token_obj('usds').balanceOf(receiver)
            print('Checking if the receiver received the fees')
            assert balAfter - balBefore == 500*1e18
        print('Checking whether farm is deployed correctly or not')
        farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
        if (creator == accounts[3]):
            event = create_tx.events['FeeCollected']
            assert not event['claimable']
            assert event['creator'] == creator
            assert event['token'] == token_obj('usds')
            assert event['amount'] == 5e20
        event = create_tx.events['FarmCreated']
        assert farm == event['farm']
        assert creator == event['creator']
        print('Checking whether farm is added to factory or not')
        assert farm == factory.farms(0)
        assert factory.farmRegistered(farm)
        print('Checking whether farm is properly initialized or not')
        assert farm.lastFundUpdateTime() == config['farm_start_time']
        assert farm.farmStartTime() == config['farm_start_time']
        assert farm.owner() == accounts[4]
        print('Everything looks good')

    def test_create_farm_with_invalid_admin(
        self, farm_deployer, config, factory
    ):
        config['farm_admin'] = ZERO_ADDRESS
        with reverts('Invalid address'):
            farm_deployer.createFarm(
                (
                    config['farm_admin'],
                    config['farm_start_time'],
                    config['cooldown_period'],
                    list(config['uniswap_pool_data'].values()),
                    list(
                        map(
                            lambda x: list(x.values()),
                            config['reward_token_data']
                        )
                    ),
                ),
                {'from': accounts[3]}
            )
