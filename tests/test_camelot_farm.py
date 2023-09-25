import math
from conftest import (
    GAS_LIMIT,
    OWNER,
    token_obj,
    fund_account,
    check_function,
    ordered_tokens,
)
# from conftest import (
#     create_deployer_farm_e20  # noqa
#       )

from brownie import (
    FarmFactory,
    accounts,
    reverts,
    Demeter_CamelotFarm,
    Demeter_CamelotFarm_Deployer,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    chain,
    interface,
    network,
    Contract,
    ZERO_ADDRESS
)
from random import randint
import pytest
import eth_utils


# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']
deployer = accounts
deployers = ['CamelotFarmDeployer_v1']
DEMETER_FACTORY = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
CAMELOT_FACTORY = '0x6EcCab422D763aC031210895C81787E87B43A652'
CAMELOT_NFT_FACTORY = '0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d'
CAMELOT_POSITION_HELPER = '0xe458018Ad4283C90fB7F5460e24C4016F81b8175'


def init_farm(deployer, farm, config):
    """Init Uniswap Farm Proxy Contract"""
    farm.initialize(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['camelot_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    return farm


def init_farm_e20(deployer, farm, config, token_a, token_b):
    """Init Uniswap Farm Proxy Contract"""
    camelot_factory = Contract.from_abi(
        'Camelot factory',
        CAMELOT_FACTORY,
        interface.ICamelotFactory.abi
    )

    lp_token = camelot_factory.getPair(token_a, token_b)
    farm.initialize(
        config['farm_start_time'],
        config['cooldown_period'],
        lp_token,
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    return farm


def deployer_constants():
    if (network.show_active() == 'arbitrum-main-fork'):
        config = {
            'CamelotFarmDeployer_v1':  {
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'protocol_factory':
                    '0x6EcCab422D763aC031210895C81787E87B43A652',
                'deployer_name': 'Demeter_Camelot_Farm'
            },
            'SushiSwapFarmDeployer_v1': {
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'protocol_factory':
                    '0xc35DADB65012eC5796536bD9864eD8773aBc74C4',
                'deployer_name': 'Demeter_SushiSwap_Farm'
            },
            'TraderJoeFarmDeployer_v1': {
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'protocol_factory':
                    '0xaE4EC9901c3076D0DdBe76A520F9E90a6227aCB7',
                'deployer_name': 'Demeter_TraderJoe_Farm'
            },
        }
        return config


def deploy_farm(deployer, contract):
    """Deploying Uniswap Farm Proxy Contract"""

    print('Deploy Camelot Farm implementation.')
    farm = contract.deploy(

        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    print('Deploy Proxy Admin.')
    # Deploy the proxy admin contract
    proxy_admin = ProxyAdmin.deploy(
        {'from': deployer, 'gas': GAS_LIMIT})

    proxy = TransparentUpgradeableProxy.deploy(
        farm.address,
        proxy_admin.address,
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    uniswap_farm = Contract.from_abi(
        'Camelot_v1',
        proxy.address,
        contract.abi
    )
    return uniswap_farm


@pytest.fixture(scope='module', autouse=True)
def setUp(config):
    global deployer, not_rwd_tkn, reward_tkn, lock_data, admin, user
    global no_lock_data, manager
    mint_position,
    deploy_farm,
    deployer = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
    admin = accounts[0]
    user = accounts[1]
    not_rwd_tkn = token_obj('frax')
    manager = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'


@pytest.fixture(scope='module', autouse=True, params=farm_names)
def config(request):
    global farm_name
    farm_name = request.param
    farm_config = constants()[farm_name]
    config = farm_config['config']

    return config


@pytest.fixture(scope='module', autouse=True)
def test_config(request):
    test_config = {
        'number_of_deposits': 2,
        'funding_data': {
            'spa': 100000e18,
            'usds': 10000e18,
            'usdc': 100000e6,
        },
        'camelot_pool_false_data': {
            'token_A':
            '0x5575552988A3A80504bBaeB1311674fCFd40aD4C',
            'token_B':
            '0xD74f5255D557944cf7Dd0E45FF521520002D5747',
        },
    }
    return test_config


@pytest.fixture(scope='module', autouse=True, params=deployers)
def deployer_config(request):
    deployers = request.param
    dep_config = deployer_constants()[deployers]
    return dep_config


@pytest.fixture(scope='module', autouse=True)
def factory(setUp):
    proxy = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'

    factory_contract = FarmFactory.at(proxy)

    print('factory owner is:', factory_contract.owner())

    return factory_contract


@pytest.fixture(scope='module', autouse=True)
def farm_deployer(deployer_config, factory):
    """Deploying Uniswap Farm Proxy Contract"""
    print('Deploy Demeter_UniV2FarmDeployer contract.')
    print(list(deployer_config.values()))
    farm_f = deployer_config['farm_factory']
    protocol = deployer_config['protocol_factory']

    farm_deployer = Demeter_CamelotFarm_Deployer.deploy(
        farm_f,
        protocol,
        {'from': deployer}
    )

    print('Register the deployer contract with the Factory.')
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )
    print('Farm Deployer Address is: ', farm_deployer)
    return farm_deployer


@pytest.fixture(scope='module', autouse=True)
def farm_contract(config):

    return deploy_farm(admin, Demeter_CamelotFarm)


@pytest.fixture(scope='module')
def farm(config, farm_contract):
    token_a = config['camelot_pool_data']['token_A']
    token_b = config['camelot_pool_data']['token_B']
    return init_farm_e20(admin, farm_contract, config, token_a, token_b)

# NOTE: This deploys the farm from farm Deployer
# @pytest.fixture(scope='module', autouse=True)
# def farm(config, farm_deployer, factory):
#     print(farm_deployer, "Farm Deployer")
#     farm_contract = create_deployer_farm_e20(
#         deployer, farm_deployer, config, factory)
#     return farm_contract


@pytest.fixture(scope='module', autouse=True)
def funding_accounts(test_config):
    token = list(test_config['funding_data'].keys())
    amount = list(test_config['funding_data'].values())
    print('balances before funding')
    for _, tkn in enumerate(token):

        print('balance of Deployer in',
              token_obj(tkn).name(), ' is',
              (token_obj(tkn).balanceOf(deployer)) /
              (10**token_obj(tkn).decimals()))

        print('balance of Farm Admin in',
              token_obj(tkn).name(), ' is',
              (token_obj(tkn).balanceOf(admin)) /
              (10**token_obj(tkn).decimals()))

        print('balance of Farm User in',
              token_obj(tkn).name(), ' is',
              (token_obj(tkn).balanceOf(user)) /
              (10**token_obj(tkn).decimals()))

    for i, tkn in enumerate(token):
        fund_account(deployer, tkn, amount[i])
        print(tkn, 'is funded by ', amount[i] /
              (math.pow(10, token_obj(tkn).decimals())), 'to Deployer')
        fund_account(admin, tkn, amount[i])
        print(tkn, 'is funded by ', amount[i] /
              (math.pow(10, token_obj(tkn).decimals())), 'to Farm Admin')
        fund_account(user, tkn, amount[i])
        print(tkn, 'is funded by ', amount[i] /
              (math.pow(10, token_obj(tkn).decimals())), 'to Farm User')

    # print(token, amount)
    return token, amount


@ pytest.fixture(scope='module', autouse=True)
def reward_token(config):
    reward_tkn = list()
    reward_tkn.append(token_obj('spa'))  # Default reward token
    for i in range(len(config['reward_token_data'])):
        reward_tkn.append(interface.ERC20(
            config['reward_token_data'][i]['reward_tkn']))
    for _, tkn in enumerate(reward_tkn):
        rwd_token_name = tkn.name()
        print('reward token name is: ', rwd_token_name)
    return reward_tkn


def mint_pos(config, dep_index):
    token_a_obj = interface.ERC20(config['camelot_pool_data']['token_A'])
    token_b_obj = interface.ERC20(config['camelot_pool_data']['token_B'])
    token_a_decimals = token_a_obj.decimals()
    token_b_decimals = token_b_obj.decimals()

    amt_a = randint(100, 1000) * 10 ** token_a_decimals
    amt_b = randint(100, 1000) * 10 ** token_b_decimals
    pos = mint_position(
        token_a_obj,
        token_b_obj,
        amt_a,
        amt_b,
        dep_index,
        user,
    )
    return pos, amt_a, amt_b


@pytest.fixture()
def minted_positions(config, test_config):
    global amount_a, amount_b
    token_id = list()
    amount_a = list()
    amount_b = list()

    for i in range(test_config['number_of_deposits']):
        pos, amt_a, amt_b = mint_pos(config, i)
        amount_a.append(amt_a)
        amount_a.append(amt_b)
        token_id.append(pos)
    print(token_id)
    return token_id


def constants():
    if (network.show_active() == 'arbitrum-main-fork'):
        config = {
            'test_farm_with_lockup': {
                'contract': Demeter_CamelotFarm,
                'config': {
                    'admin': deployer[0],
                    'farm_start_time': chain.time()+2000,
                    'cooldown_period': 21,
                    'camelot_pool_data': {
                        'token_A':
                            '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                        'token_B':
                            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                        'token_C':
                            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    },
                    'reward_token_data': [
                        # {
                        #     'reward_tkn':
                        #     '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
                        #     'tkn_manager': OWNER,
                        # },
                        # {
                        #     'reward_tkn':
                        #     '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                        #     'tkn_manager': OWNER,
                        # },
                    ],

                }
            },

            'test_farm_without_lockup': {
                'contract': Demeter_CamelotFarm,
                'config': {
                    'admin': deployer[0],
                    'farm_start_time': chain.time()+2000,
                    'cooldown_period': 0,

                    'camelot_pool_data': {
                        'token_A':
                            '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                        'token_B':
                            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                        'token_C':
                            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    },
                    'reward_token_data': [
                        # {
                        #     'reward_tkn':
                        #     '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                        #     'tkn_manager': OWNER,
                        # },
                        # {
                        #     'reward_tkn':
                        #     '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                        #     'tkn_manager': OWNER,
                        # },
                    ],

                }
            },


        }
        return config


def get_lp_token(token1, token2):
    camelot_factory = Contract.from_abi(
        'Camelot factory',
        CAMELOT_FACTORY,
        interface.ICamelotFactory.abi
    )
    lp_token = camelot_factory.getPair(token1, token2)
    nft_pool_factory = Contract.from_abi(
        'Camelot: NFTpoolFactory',
        CAMELOT_NFT_FACTORY,
        interface.INFTPoolFactory.abi
    )
    nft_pool_addr = nft_pool_factory.getPool(lp_token)

    pool = interface.INFTPool(nft_pool_addr)
    return lp_token, nft_pool_addr, pool


def mint_position(
    token1,
    token2,
    amount1,
    amount2,
    deposit_index,
    user,

):
    # provide initial liquidity

    position_helper = Contract.from_abi(
        'PositionHelper',
        CAMELOT_POSITION_HELPER,
        interface.IPositionHelper.abi
    )
    t1, a1, t2, a2 = ordered_tokens(token1, amount1, token2, amount2)
    _, nft_pool_addr, pool = get_lp_token(token1, token2)
    print('pool address is:', nft_pool_addr)
    print('Token A: ', t1)
    print('Token A Name: ', t1.name())
    print('Token A Precision: ', t1.decimals())
    print('Amount A: ', a1/(10 ** t1.decimals()))
    print('Token B: ', t2)
    print('Token B Name: ', t2.name())
    print('Token B Precision: ', t2.decimals())
    print('Amount B: ', a2/(10 ** t2.decimals()))

    t1.approve(position_helper, a1, {'from': user})
    t2.approve(position_helper, a2, {'from': user})
    deadline = 7200 + chain.time()  # deadline: 2 hours
    _ = position_helper.addLiquidityAndCreatePosition(
        t1,
        t2,
        a1,
        a2,
        0,  # minimum amount of token1 expected
        0,  # minimum amount of token2 expected
        deadline,
        user,
        nft_pool_addr,
        0,
        {'from': user}
    )

    token_id = pool.tokenOfOwnerByIndex(user, deposit_index)
    return token_id


def add_rewards(farm, reward_token, funding_accounts):
    farm_rewards = list()
    key, amount = funding_accounts
    for i, tkn in enumerate(reward_token):
        token_obj(key[i]).approve(farm, 2*amount[i], {'from': admin})
        tx = farm.addRewards(
            tkn, 10000*10**tkn.decimals(),
            {'from': admin})
        farm_rewards.append(tx)
    return farm_rewards


def set_rewards_rate(farm, reward_token):
    rewards_rate = list()
    if (farm.cooldownPeriod() != 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            rwd_amt_lock = 2*rwd_amt_no_lock
            tx = farm.setRewardRate(tkn,
                                    [rwd_amt_no_lock,
                                     rwd_amt_lock],
                                    {'from': farm.SPA_TOKEN_MANAGER()})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_amt_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_amt_lock
        print('rewards rate changed and checked!!')
        return rewards_rate
    if (farm.cooldownPeriod() == 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            tx = farm.setRewardRate(tkn,
                                    [rwd_amt_no_lock],
                                    {'from': farm.SPA_TOKEN_MANAGER()})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_amt_no_lock
        print('rewards rate changed and checked!!')
        return rewards_rate


def set_invalid_rewards_rate_length(farm, reward_token):

    if (farm.cooldownPeriod() != 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            farm.setRewardRate(tkn,
                               [rwd_amt_no_lock],
                               {'from': manager})
        return print('invalid lockup rewards rate length passed!')
    if (farm.cooldownPeriod() == 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            rwd_amt_lock = 2*rwd_amt_no_lock
            farm.setRewardRate(tkn,
                               [rwd_amt_no_lock, rwd_amt_lock],
                               {'from': manager})
        return print('invalid non-lockup rewards rate length passed!')


def create_deposit(farm, config, test_config, minted_positions, is_locked):
    """
    This helper function deposits into farms
    """

    if is_locked is True:
        is_locked = (
            '0x0000000000000000000000000000000000000000000000000000000000000001')  # noqa
    else:
        is_locked = (
            '0x0000000000000000000000000000000000000000000000000000000000000000')  # noqa
    token_a = config['camelot_pool_data']['token_A']
    token_b = config['camelot_pool_data']['token_B']
    number_deposits = test_config['number_of_deposits']
    print('number of Deposits are ', number_deposits)
    global amount
    a, b, pool = get_lp_token(token_a, token_b)
    deposit = list()

    for i in range(len(minted_positions)):
        deposit_txn = pool.safeTransferFrom(
            user,
            farm.address,
            minted_positions[i],
            is_locked,
            {'from': user},
        )
        deposit.append(deposit_txn)

        assert deposit_txn.events['Deposited']['account'] == user
        assert deposit_txn.events['Deposited']['tokenId'] == \
            minted_positions[i]
        # assert deposit_txn.events['Transfer']['to'] == farm.address
        # assert deposit_txn.events['Deposited']['locked'] is is_locked
    print('Deposit checks passed ✅✅')
    return deposit


def create_deposits(farm, test_config, minted_positions, config):
    """
    This helper function deposits into farms
    """
    if (farm.cooldownPeriod() != 0):
        print('lockup deposit')
        return create_deposit(
            farm,
            config,
            test_config,
            minted_positions,
            True
        )
    elif (farm.cooldownPeriod() == 0):
        print('no lockup deposit')
        return create_deposit(
            farm,
            config,
            test_config,
            minted_positions,
            False
        )


# @pytest.mark.skip()
class Test_initialization:

    def test_initialization_reward_already_added(
        self, farm_contract, config
    ):
        rewardData = [
            {
                'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': admin,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': admin,
            },
        ]
        with reverts('Reward token already added'):
            farm_contract.initialize(
                config['farm_start_time'],
                config['cooldown_period'],
                config['camelot_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': admin, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_farm_start_time(
        self, config, farm_contract
    ):
        with reverts('Invalid farm startTime'):
            farm_contract.initialize(
                chain.time() - 1,
                config['cooldown_period'],
                config['camelot_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     config['reward_token_data'])),
                {'from': admin, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_cooldown_period(
        self, farm_contract, config
    ):
        # Test the case with max cooldown
        with reverts('Invalid cooldown period'):
            farm_contract.initialize(
                config['farm_start_time'],
                10000,
                config['camelot_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     config['reward_token_data'])),
                {'from': admin, 'gas_limit': GAS_LIMIT},
            )

    def test_initialization_rewards_more_than_four(
        self, farm_contract, config
    ):
        rewardData = [
            {
                'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': admin,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': admin,
            },
            {
                'reward_tkn':
                    '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    'tkn_manager': admin,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': admin,
            },
            {
                'reward_tkn':
                    '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    'tkn_manager': admin,
            },
        ]
        with reverts('Invalid reward data'):
            farm_contract.initialize(
                config['farm_start_time'],
                config['cooldown_period'],
                config['camelot_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': admin, 'gas_limit': GAS_LIMIT},
            )

    def test_initialization(self, farm):

        assert farm.SPA() == '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'
        manager = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
        assert farm.SPA_TOKEN_MANAGER() == manager
        assert farm.COMMON_FUND_ID() == 0
        assert farm.LOCKUP_FUND_ID() == 1
        assert farm.MIN_COOLDOWN_PERIOD() == 1
        assert farm.MAX_NUM_REWARDS() == 4
        assert not farm.isPaused()
        assert not farm.isClosed()


# @pytest.mark.skip()
class Test_private_functions:

    def test_subscribe_reward_fund(self, farm):
        func_name = '_subscribeRewardFund'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid fund id'):
            farm._subscribeRewardFund(4, 1, 1, {'from': admin})

    def test_unsubscribe_reward_fund(self, farm):
        func_name = '_unsubscribeRewardFund'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid fund id'):
            farm._unsubscribeRewardFund(4, admin, 1, {'from': admin})

    def test_get_acc_rewards(self, farm):
        func_name = '_getAccRewards'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        farm._getAccRewards(0, 0, chain.time())


# @pytest.mark.skip()
class Test_admin_function:
    @pytest.fixture()
    def setup_rewards(self, fn_isolation, farm,
                      test_config, reward_token, funding_accounts,
                      minted_positions, config):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)

        return tx

    # @pytest.mark.skip()
    class Test_on_ERC721_received:

        # def test_incorrect_liquidity(self, farm, config):
        #     with reverts('onERC721Received: no data'):
        #         token_a_obj = interface.ERC20(
        #             config['camelot_pool_data']['token_A'])
        #         token_b_obj = interface.ERC20(
        #             config['camelot_pool_data']['token_B'])
        #         token_c_obj = interface.ERC20(
        #             config['camelot_pool_data']['token_C'])

        #         token_a_decimals = token_a_obj.decimals()
        #         token_b_decimals = token_b_obj.decimals()
        #         token_c_decimals = token_c_obj.decimals()

        #         amt_a = randint(100, 1000) * 10 ** token_a_decimals
        #         amt_b = randint(100, 1000) * 10 ** token_b_decimals
        #         amt_c = randint(100, 1000) * 10 ** token_c_decimals
        #         a, b, pool = get_lp_token(
        #             token_a_obj.address, token_b_obj.address)
        #         pos = mint_position(
        #             token_a_obj,
        #             token_b_obj,
        #             amt_a,
        #             amt_b,
        #             0,
        #             user,
        #         )

        #         pool.safeTransferFrom(
        #             user,
        #             farm.address,
        #             pos,
        #             {'from': user},
        #         )

        def test_incorrect_data(self, farm, config, minted_positions):
            token_id = minted_positions
            with reverts('onERC721Received: no data'):
                token_a_obj = interface.ERC20(
                    config['camelot_pool_data']['token_A'])
                token_b_obj = interface.ERC20(
                    config['camelot_pool_data']['token_B'])

                _, _, pool = get_lp_token(
                    token_a_obj.address, token_b_obj.address)

                pool.safeTransferFrom(
                    user,
                    farm.address,
                    token_id[0],
                    {'from': user},
                )

        def test_incorrect_nft(self, farm, config):
            with reverts('onERC721Received: incorrect nft'):
                token_a_obj = interface.ERC20(
                    config['camelot_pool_data']['token_A'])
                token_b_obj = interface.ERC20(
                    config['camelot_pool_data']['token_B'])
                token_c_obj = interface.ERC20(
                    config['camelot_pool_data']['token_C'])

                token_a_decimals = token_a_obj.decimals()
                _ = token_b_obj.decimals()
                token_c_decimals = token_c_obj.decimals()

                amt_a = randint(100, 1000) * 10 ** token_a_decimals
                amt_c = randint(100, 1000) * 10 ** token_c_decimals

                pos = mint_position(
                    token_a_obj,
                    token_c_obj,
                    amt_a,
                    amt_c,
                    0,
                    user,
                )
                a, b, pool = get_lp_token(
                    token_a_obj.address, token_c_obj.address)
                _ = pool.safeTransferFrom(
                    user,
                    farm.address,
                    pos,
                    '0x0000000000000000000000000000000000000000000000000000000000000000',  # noqa
                    {'from': user},
                )

        def test_zero_address(self, farm):
            with reverts('Invalid address'):
                manager = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
                farm.updateTokenManager(
                    farm.SPA(), ZERO_ADDRESS, {'from': manager})

    # @pytest.mark.skip()
    class Test_update_Token_Manager:

        def test_invalid_token_manager(self, farm):
            with reverts('Not the token manager'):
                farm.updateTokenManager(farm.SPA(), accounts[5], {
                    'from': accounts[4]})

        def test_zero_address(self, farm):
            with reverts('Invalid address'):
                manager = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
                farm.updateTokenManager(
                    farm.SPA(), ZERO_ADDRESS, {'from': manager})

    # @pytest.mark.skip()
    class Test_update_cooldown:

        def test_updateCooldownPeriod_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.updateCooldownPeriod(
                    1, {'from': accounts[1], 'gas_limit': GAS_LIMIT})

        def test_farm_with_no_cooldown(self, farm):
            if (farm_name == 'test_farm_without_lockup'):
                with reverts('Farm does not support lockup'):
                    farm.updateCooldownPeriod(
                        3, {'from': admin, 'gas_limit': GAS_LIMIT})

        def test_incorrect_cooldown(self, farm):
            if (farm_name == 'test_farm_with_lockup'):
                with reverts('Invalid cooldown period'):
                    farm.updateCooldownPeriod(
                        farm.MIN_COOLDOWN_PERIOD() - 1,
                        {'from': admin, 'gas_limit': GAS_LIMIT}
                    )

                with reverts('Invalid cooldown period'):
                    farm.updateCooldownPeriod(
                        farm.MAX_COOLDOWN_PERIOD() + 1,
                        {'from': admin, 'gas_limit': GAS_LIMIT}
                    )

        def test_update_cooldown(
            self,
            fn_isolation,
            farm,
            config,
            minted_positions,
            test_config
        ):
            if (farm_name == 'test_farm_with_lockup'):
                old_cooldown = farm.cooldownPeriod()
                new_cooldown = 5

                # Create a deposit with initial cooldown period
                _ = create_deposit(
                    farm, config, test_config, minted_positions, True
                )
                tx = farm.updateCooldownPeriod(
                    5, {'from': admin, 'gas_limit': GAS_LIMIT})

                event = tx.events['CooldownPeriodUpdated']
                assert event['newCooldownPeriod'] == new_cooldown
                assert event['oldCooldownPeriod'] == old_cooldown
                assert farm.cooldownPeriod() == new_cooldown

                print('\nAsserting positions before and after cooldown update')
                deposits = farm.getNumDeposits(user)
                d1 = farm.getDeposit(user, (deposits - 2))

                assert d1.dict()['cooldownPeriod'] == old_cooldown
                assert farm.cooldownPeriod() == new_cooldown

    # @pytest.mark.skip()
    class Test_update_farm_start_time:
        def test_updateFarmStartTime_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.updateFarmStartTime(
                    chain.time() + 2, {'from': accounts[2]})

        def test_updateFarmStartTime_for_started_farm(self, farm):
            chain.mine(1, farm.farmStartTime())
            with reverts('Farm already started'):
                farm.updateFarmStartTime(
                    chain.time()+2, {'from': admin})

        def test_updateFarmStartTime_in_past(self, farm):
            with reverts('Time < now'):
                farm.updateFarmStartTime(
                    chain.time()-2, {'from': admin})

        def test_updateFarmStartTime(self, farm):
            newTime = chain.time() + 500
            tx = farm.updateFarmStartTime(
                newTime, {'from': admin})
            event = tx.events['FarmStartTimeUpdated']
            assert newTime == event['newStartTime']
            assert newTime == farm.farmStartTime()
            assert newTime == farm.lastFundUpdateTime()

    # @pytest.mark.skip()
    class Test_farm_pause_switch:

        def test_farmPauseSwitch_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.farmPauseSwitch(
                    True, {'from': accounts[2]})

        def test_farmPauseSwitch_try_false(self, farm):
            with reverts('Farm already in required state'):
                farm.farmPauseSwitch(
                    False, {'from': admin})

        def test_farmPauseSwitch_pause(self, farm):
            tx = farm.farmPauseSwitch(
                True, {'from': admin})
            event = tx.events['FarmPaused']
            assert event['paused']
            with reverts('Farm paused'):
                farm.initiateCooldown(2, {'from': accounts[2]})

        def test_farmPauseSwitch_unpause(self, farm):
            farm.farmPauseSwitch(
                True, {'from': admin})
            tx = farm.farmPauseSwitch(
                False, {'from': admin})
            event = tx.events['FarmPaused']
            assert not event['paused']

    def test_deposit_paused(self, farm, test_config, minted_positions, config):
        farm.farmPauseSwitch(True, {'from': admin})
        with reverts('Farm paused'):
            create_deposits(farm, test_config, minted_positions, config)

    def test_claim_rewards_paused(self, farm, setup_rewards, reward_token):
        chain.mine(10, None, 1000)
        farm.farmPauseSwitch(True, {'from': admin})
        chain.mine(10, None, 1000)
        print('claiming rewards for the first time after pausing the farm')
        for i in range(len(setup_rewards)):
            _ = farm.claimRewards(0, {'from': user})
            # for i in range(len(reward_token)):
            #     assert tx.events['RewardsClaimed']['rewardAmount'][i] != 0
        print('checked first claimed rewards !=  0')
        print('claiming rewards for the second time after pausing the farm')
        for i in range(len(setup_rewards)):
            tx2 = farm.claimRewards(0, {'from': user})
            for i in range(len(reward_token)):
                assert tx2.events['RewardsClaimed']['rewardAmount'][i] == 0
        print('checked reward claimed for second time = 0')

    def test_withdraw_paused_lockup_farm(self, farm, setup_rewards):
        chain.mine(10, None, 1000)
        farm.farmPauseSwitch(True, {'from': admin})
        chain.mine(10, None, 1000)
        tx = farm.withdraw(0, {'from': user})
        if(farm.cooldownPeriod() > 0):
            assert len(tx.events['PoolUnsubscribed']) == 2

    def test_change_reward_rates_paused(self, farm, reward_token):
        rwd_rate_no_lock = 2e15
        rwd_rate_lock = 4e15
        tkn_mgr = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
        if (farm_name == 'test_farm_with_lockup'):
            farm.farmPauseSwitch(True, {'from': admin})
            tx = farm.setRewardRate(reward_token[0],
                                    [rwd_rate_no_lock, rwd_rate_lock],
                                    {'from': tkn_mgr, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_rate_lock
            print('unpausing the farm')
            farm.farmPauseSwitch(False, {'from': admin})
            chain.mine(10, None, 1000)

            tx = farm.getRewardRates(reward_token[0])

            assert tx[0] == rwd_rate_no_lock
            assert tx[1] == rwd_rate_lock

        elif (farm_name == 'test_farm_without_lockup'):
            farm.farmPauseSwitch(True, {'from': admin})
            tx = farm.setRewardRate(reward_token[0], [rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock

            print('unpausing the farm')
            farm.farmPauseSwitch(False, {'from': admin})
            chain.mine(10, None, 1000)
            tx = farm.getRewardRates(reward_token[0])
            assert tx[0] == rwd_rate_no_lock

    # @pytest.mark.skip()
    class Test_close_farm:
        def test_closeFarm_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.closeFarm({'from': accounts[3]})

        def test_deposit_closed(self, farm,  test_config,
                                minted_positions, config):
            farm.closeFarm({'from': admin})
            with reverts('Farm paused'):
                create_deposits(farm, test_config,
                                minted_positions, config)

        def test_withdraw_closed_lockup_farm(self, farm, setup_rewards):
            if (farm.cooldownPeriod() != 0):
                chain.mine(10, None, 1000)
                farm.closeFarm({'from': admin})
                chain.mine(10, None, 1000)
                _ = farm.withdraw(0, {'from': user})

        def test_close_farm_stop_reward_accrual(self, farm, setup_rewards,
                                                reward_token):
            tkn_mgr = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
            _ = farm.recoverRewardFunds(farm.SPA(), 0, {'from': tkn_mgr})
            _ = farm.recoverRewardFunds(farm.SPA(), 1, {'from': tkn_mgr})
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                assert tx != 0
            tx = farm.closeFarm({'from': admin})
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                assert tx == 0

        def test_close_farm_recover_funds(self, farm, setup_rewards,
                                          reward_token):
            rewards_balance = list()
            rewards_rate = list()
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                ty = farm.getRewardRates(token)
                rewards_rate.append(ty)
                rewards_balance.append(tx)
            print('reward Balances are:', rewards_balance)

            tx = farm.closeFarm({'from': admin})
            if (farm_name == 'test_farm_with_lockup'):
                for i, token in enumerate(reward_token):
                    assert tx.events['FundsRecovered'][i]['amount'] >= \
                        rewards_balance[i] - \
                        rewards_rate[i][0]-rewards_rate[i][1]
                    assert tx.events['FundsRecovered'][i]['account'] == manager
                    assert tx.events['FundsRecovered'][i]['rwdToken'] == token
                    assert tx.events['RewardRateUpdated'][i]['newRewardRate'] \
                        == [0, 0]
            if (farm_name == 'test_farm_without_lockup'):
                for i, token in enumerate(reward_token):
                    assert tx.events['FundsRecovered'][i]['amount'] >= \
                        rewards_balance[i] - rewards_rate[i][0]
                    assert tx.events['FundsRecovered'][i]['account'] == manager
                    assert tx.events['FundsRecovered'][i]['rwdToken'] == token
                    assert tx.events['RewardRateUpdated'][i]['newRewardRate'] \
                        == [0]

        def test_close_farm_claim_rewards(self, farm):
            farm.closeFarm({'from': admin})
            with reverts('Farm closed'):
                farm.claimRewards(
                    accounts[2], 2, {'from': accounts[2]})

    # @pytest.mark.skip()
    class Test_recover_ERC20:
        def test_recoverERC20_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.recoverERC20(not_rwd_tkn, {'from': accounts[4]})

        def test_recoverERC20_reward_token(self, farm, reward_token):
            with reverts('Can\'t withdraw rewardToken'):
                farm.recoverERC20(reward_token[0], {'from': admin})

        def test_recoverERC20_zero_balance(self, farm):
            with reverts('Can\'t withdraw 0 amount'):
                farm.recoverERC20(not_rwd_tkn, {'from': admin})

        def test_recoverERC20(self, farm):
            balance = 100 * 1e18
            fund_account(farm, 'frax', balance)
            beforeRecovery = not_rwd_tkn.balanceOf(admin)
            tx = farm.recoverERC20(not_rwd_tkn, {'from': admin})
            afterRecovery = not_rwd_tkn.balanceOf(admin)
            event = tx.events['RecoveredERC20']
            assert event['token'] == not_rwd_tkn
            assert event['amount'] == balance
            assert afterRecovery - beforeRecovery == balance

        def test_recover_zero_amount(self, farm):
            farm_token = '0x495dabd6506563ce892b8285704bd28f9ddcae65'
            with reverts("Can't withdraw 0 amount"):
                farm.recoverERC20(farm_token, {'from': admin})


# @pytest.mark.skip()
class Test_view_functions:
    # @pytest.mark.skip()
    class Test_compute_rewards:
        def get_rewards(self, msg, farm, deposit):
            print(f'\n{msg}')
            rewards = []
            chain.mine(10, None, 86400)
            _ = farm.computeRewards(user, 0)
            _ = tx = farm.computeRewards(user, 0)
            for i in range(len(deposit)):
                tx = farm.computeRewards(user, 0)
                rewards.append(tx)
                print('rewards calculated for deposit ',
                      i, 'are: ', rewards[i])
            return rewards

        def test_computeRewards_invalid_deposit(self, farm,
                                                test_config,
                                                minted_positions, config):
            deposit = create_deposits(farm, test_config,
                                      minted_positions, config)
            with reverts('Deposit does not exist'):
                farm.computeRewards(user, len(deposit)+1)

        def test_after_farm_starts(self, fn_isolation, farm,
                                   funding_accounts,
                                   test_config,
                                   reward_token,
                                   minted_positions, config):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(farm, test_config,
                                      minted_positions, config)
            _ = self.get_rewards('Compute rwd after farm start', farm, deposit)

        def test_during_farm_pause(
            self,
            fn_isolation,
            farm,
            funding_accounts,
            test_config,
            reward_token,
            minted_positions,
            config
        ):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposits = create_deposits(farm, test_config, minted_positions,
                                       config)
            chain.mine(1, None, 86400)

            _ = farm.farmPauseSwitch(True, {'from': farm.owner()})
            assert farm.isPaused()
            initial_rwd = self.get_rewards(
                'Compute rwd after farm pause day1', farm, deposits
            )

            rwd_after_pause = self.get_rewards(
                'Compute rwd after farm paused day2', farm, deposits
            )

            assert initial_rwd == rwd_after_pause

            _ = farm.closeFarm({'from': farm.owner()})
            assert farm.isClosed()

            rwd_after_close = self.get_rewards(
                'Compute rwd after farm closed', farm, deposits
            )
            assert initial_rwd == rwd_after_close

    def test_getNumDeposits(
        self,
        farm,
        test_config,
        minted_positions,
        config
    ):

        _ = create_deposits(farm, test_config,
                            minted_positions, config)
        assert farm.getNumDeposits(user) == 2

    def test_getNumSubscriptions(
        self,
        farm,
        test_config,
        minted_positions,
        config
    ):
        deposits = create_deposits(farm, test_config, minted_positions, config)
        for i in range(len(deposits)):
            tx = farm.getNumSubscriptions(
                deposits[i].events['Deposited']['tokenId'])
            print('Token ID subscriptions are: ', tx)

    # @pytest.mark.skip()
    class Test_get_subscription_info:
        def test_getSubscriptionInfo_invalid_subscription(
            self,
            farm,
            test_config,
            minted_positions,
            config
        ):
            id_minted = create_deposits(
                farm, test_config, minted_positions, config)
            with reverts('Subscription does not exist'):
                farm.getSubscriptionInfo(
                    id_minted[0].events['Deposited']['tokenId'], 3)

        def test_getSubscriptionInfo(self, farm,
                                     test_config, minted_positions, config):
            tx = create_deposits(farm, test_config, minted_positions, config)
            _ = farm.getSubscriptionInfo(
                tx[0].events['Deposited']['tokenId'], 0)

    def test_invalid_reward_rates_length(self, farm, reward_token):
        if (farm_name == 'test_farm_with_lockup'):
            with reverts('Invalid reward rates length'):
                farm.setRewardRate(reward_token[0], [1000], {
                                   'from': manager, 'gas_limit': GAS_LIMIT})
        elif (farm_name == 'test_farm_without_lockup'):
            with reverts('Invalid reward rates length'):
                farm.setRewardRate(reward_token[0], [1000, 2000], {
                                   'from': manager, 'gas_limit': GAS_LIMIT})

    def test_reward_rates_data(self, farm, reward_token):
        rwd_rate_no_lock = 1e15
        rwd_rate_lock = 2e15

        if (farm_name == 'test_farm_with_lockup'):
            tx = farm.setRewardRate(reward_token[0],
                                    [rwd_rate_no_lock, rwd_rate_lock],
                                    {'from': manager, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_rate_lock
        elif (farm_name == 'test_farm_without_lockup'):
            tx = farm.setRewardRate(reward_token[0], [rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
        print('changing reward rates for the second time........ ')
        new_rwd_rate_no_lock = 15e14
        new_rwd_rate_lock = 3e15
        if (farm_name == 'test_farm_with_lockup'):
            tx = farm.setRewardRate(reward_token[0],
                                    [new_rwd_rate_no_lock, new_rwd_rate_lock],
                                    {'from': OWNER, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['oldRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['oldRewardRate'][1] == \
                rwd_rate_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                new_rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                new_rwd_rate_lock
        elif (farm_name == 'test_farm_without_lockup'):

            tx = farm.setRewardRate(reward_token[0], [new_rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['oldRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                new_rwd_rate_no_lock

    # @pytest.mark.skip()
    class Test_get_reward_fund_info:
        def test_getRewardFundInfo_more_than_added(self, farm):
            with reverts('Reward fund does not exist'):
                farm.getRewardFundInfo(3)

        def test_getRewardFundInfo(self, farm, funding_accounts, reward_token,
                                   test_config, minted_positions, config):
            total_liquidity = 0
            _ = add_rewards(farm, reward_token, funding_accounts)
            rate = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(
                farm, test_config, minted_positions, config)
            fund_id = 0
            if(farm_name == 'test_farm_with_lockup'):
                fund_id = 1
            res = farm.getRewardFundInfo(fund_id)

            for rwd, _ in enumerate(reward_token):
                assert res[1][rwd] == \
                    rate[rwd].events[
                        'RewardRateUpdated'
                ]['newRewardRate'][fund_id]
            for _, dep in enumerate(deposit):
                total_liquidity += dep.events['Deposited']['liquidity']
            # assert res[0] == total_liquidity

    # @pytest.mark.skip()
    class Test_get_reward_balance:
        @pytest.fixture()
        def setup(self, fn_isolation, farm,
                  test_config,

                  reward_token, funding_accounts, minted_positions, config):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            tx = create_deposits(farm, test_config, minted_positions, config)
            chain.mine(10, None, 86400)
            return tx

        def test_getRewardBalance_invalid_rwdToken(self, farm):
            with reverts('Invalid _rwdToken'):
                farm.getRewardBalance(not_rwd_tkn, {'from': user})

        def test_getRewardBalance_rewardsAcc_more_than_supply(self,
                                                              reward_token,
                                                              farm, setup):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': user})
                print(tx, 'is reward balance')

        def test_getRewardBalance(self, farm, setup, reward_token):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': user})
                print(tx, 'is reward balance')


# @pytest.mark.skip()
class Test_recover_reward_funds:
    @pytest.fixture()
    def setup(self, fn_isolation, farm,
              test_config,
              reward_token, funding_accounts, minted_positions, config):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)
        return tx

    def test_recover_reward_funds(self, reward_token, setup, farm):
        recovered_funds = list()
        for i, tkn in enumerate(reward_token):
            tx = farm.recoverRewardFunds(tkn, farm.getRewardBalance(
                tkn, {'from': manager}), {'from': manager})
            recovered_funds.append(tx)
            assert recovered_funds[i].events['FundsRecovered']['rwdToken'] == \
                tkn
            assert recovered_funds[i].events['FundsRecovered']['amount'] != 0
            assert recovered_funds[i].events['FundsRecovered']['account'] == \
                manager
            # Reward Accrual Stopped
            assert farm.getRewardBalance(tkn, {'from': OWNER}) == 0
            farm.computeRewards(user, 0)
            farm.computeRewards(user, 0)
            farm.computeRewards(user, 0)

    def test_recover_reward_funds_uint256_max(self, reward_token, setup, farm):
        UINT256_MAX = \
            115792089237316195423570985008687907853269984665640564039457584007913129639935  # noqa
        for token in reward_token:
            init_bal = farm.getRewardBalance(token)
            tx = farm.recoverRewardFunds(token, UINT256_MAX, {'from': OWNER})
            ev = tx.events['FundsRecovered']
            assert ev['amount'] <= init_bal


# @pytest.mark.skip()
class Test_set_reward_rate:

    def test_set_reward_rate(self, farm, reward_token):
        set_rewards_rate(farm, reward_token)

    def test_set_invalid_reward_rate_length(self, farm, reward_token):
        set_rewards_rate(farm, reward_token)


# @pytest.mark.skip()
class Test_add_rewards:
    def test_invalid_reward(self, farm):
        with reverts('Invalid reward token'):
            farm.addRewards(ZERO_ADDRESS, 10e2, {'from': admin})

    def test_add_rewards(self, fn_isolation, farm,
                         reward_token,
                         funding_accounts):
        tx = add_rewards(farm, reward_token, funding_accounts)

        for i, tkn in enumerate(reward_token):
            assert tkn.address == \
                tx[i].events['RewardAdded']['rwdToken']
            assert tx[i].events['RewardAdded']['amount'] == 10000 * \
                10**tkn.decimals()
            print('Reward token', tkn.name(), 'is checked!!')
            assert tx[i].events['Transfer']['from'] == admin
            print('checked the spender for the reward token',
                  tkn.name())


# @pytest.mark.skip()
class Test_deposit:

    def test_lockup_disabled(
        self,
        farm,
        test_config,
        minted_positions,
        config
    ):
        if (farm.cooldownPeriod() == 0):
            with reverts('Lockup functionality is disabled'):
                create_deposit(farm, config, test_config,
                               minted_positions, True)

    def test_successful_deposit_with_lockup(
        self,
        farm,
        test_config,
        minted_positions,
        config
    ):
        _ = create_deposits(farm, test_config, minted_positions, config)

    def test_successful_deposit_without_lockup(
        self,
        farm,
        test_config,
        minted_positions,
        config
    ):
        _ = create_deposits(farm, test_config, minted_positions, config)


# @pytest.mark.skip()
class Test_claim_rewards:
    @pytest.fixture()
    def setup(self, fn_isolation, farm,  test_config,
              reward_token, funding_accounts, minted_positions, config):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)

        return tx

    def test_incorrect_nftHarvest_sender(self, farm, minted_positions):
        with reverts('Not Allowed'):
            farm.onNFTHarvest(
                user,
                accounts[0],
                minted_positions[0],
                1,
                1,
                {'from': user}
            )

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.claimRewards(
                len(setup)+1,
                {'from': user}
            )

    def test_claim_pool_rewards(self, farm, setup):

        grail = interface.ERC20('0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8')
        xgrail = interface.ERC20('0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b')
        grailRewards = 0
        xGrailRewards = 0

        for i, txn in enumerate(setup):
            token_id = txn.events['Deposited']['tokenId']
            interface.INFTPool(farm.nftPool()).updatePool(
                {'from': user})
            _ = farm.computePoolRewards(token_id)
            interface.INFTPool(farm.nftPool()).updatePool(
                {'from': user})
            claim = farm.claimPoolRewards(i, {'from': user})
            grailRewards += claim.events['PoolRewardsCollected']['grailAmt']
            xGrailRewards += claim.events['PoolRewardsCollected']['xGrailAmt']
            print('total grail Received:', grailRewards/1e18)
            print('total xGrail Received:', xGrailRewards/1e18)
            assert grail.balanceOf(user) == grailRewards
            assert xgrail.balanceOf(user) == xGrailRewards
            # assert (claim.events['PoolRewardsCollected']['grailAmt'] + \
            #   claim.events['PoolRewardsCollected']['xGrailAmt'] - compute) \
            #  compute < 1e-4

        print('claiming rewards check passed! 😁😁😁')

    def test_claim_rewards_for_self(self, farm, setup):
        claimed_tx = list()
        if (farm_name == 'test_farm_with_lockup'):
            for i, txn in enumerate(setup):
                tx = farm.claimRewards(i, {'from': user})
                claimed_tx.append(tx)
                assert len(tx.events['RewardsClaimed']) == 2
                assert txn.events['Deposited']['tokenId'] == \
                    claimed_tx[i].events['RewardsClaimed']['tokenId']
                assert txn.events['Deposited']['account'] == \
                    claimed_tx[i].events['RewardsClaimed']['account']
                assert txn.events['Deposited']['liquidity'] == \
                    claimed_tx[i].events['RewardsClaimed']['liquidity']
            print('claiming rewards check passed!')
        elif (farm_name == 'test_farm_without_lockup'):
            for i, txn in enumerate(setup):
                tx = farm.claimRewards(i, {'from': user})
                claimed_tx.append(tx)
                assert len(tx.events['RewardsClaimed']) == 1
                assert txn.events['Deposited']['tokenId'] == \
                    claimed_tx[i].events['RewardsClaimed']['tokenId']
                assert txn.events['Deposited']['account'] == \
                    claimed_tx[i].events['RewardsClaimed']['account']
                assert txn.events['Deposited']['liquidity'] == \
                    claimed_tx[i].events['RewardsClaimed']['liquidity']
            print('claiming rewards check passed!')

    def test_claim_rewards_for_other_address(self, farm, setup):
        with reverts('Deposit does not exist'):
            _ = farm.claimRewards(0, {'from': accounts[2]})

    def test_multiple_reward_claims(self, farm, setup):
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': user})
            # for i, tx in enumerate(setup):

        chain.mine(10, None, 86400)
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': user})

        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': user})
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': user})

    def test_claiming_without_rewards(self, farm,
                                      test_config, minted_positions, config):
        tx = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)
        for i in range(len(tx)):
            tx = farm.claimRewards(0, {'from': user})


# @pytest.mark.skip()
class Test_initiate_cooldown:
    @ pytest.fixture(scope='function')
    def setup(
        self,
        farm,
        test_config,
        reward_token,
        funding_accounts,
        fn_isolation,
        minted_positions,
        config
    ):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            _ = farm.claimRewards(0, {'from': user})

        return deposit

    def test_no_lockup(self, farm, setup):
        if (farm.cooldownPeriod() == 0):
            with reverts('Can not initiate cooldown'):
                farm.initiateCooldown(
                    0,
                    {'from': user}
                )

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.initiateCooldown(
                len(setup)+1,
                {'from': user}
            )

    def test_for_unlocked_deposit(self, farm, setup):

        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': user}
            )

    def test_initiate_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': user}
            )


# @pytest.mark.skip()
class Test_withdraw:
    @pytest.fixture(scope='function')
    def setup(
        self,
        farm,
        test_config,
        reward_token,
        funding_accounts,
        fn_isolation,
        minted_positions,
        config
    ):
        claimed = list()
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, test_config, minted_positions, config)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            claimed.append(farm.claimRewards(0, {'from': user}))

        return deposit, claimed

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.withdraw(
                len(setup) + 1,
                {'from': user}
            )

    def test_farm_paused(self, farm, setup):
        withdraw_txns = list()
        farm.farmPauseSwitch(True, {'from': admin})
        for i in range(len(setup)):
            withdraw_txns.append(farm.withdraw(0, {'from': user}))

    def test_cooldown_not_initiated(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            with reverts('Please initiate cooldown'):
                for i in range(len(setup)):
                    farm.withdraw(0, {'from': user})

    def test_deposit_in_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': user}
            )
            with reverts('Deposit is in cooldown'):
                farm.withdraw(
                    0,
                    {'from': user}
                )

    def test_withdraw(self, setup, farm):
        withdraws = list()
        if (farm.cooldownPeriod() != 0):
            for i in range(len(setup)):
                farm.initiateCooldown(
                    0,
                    {'from': user}
                )
                chain.mine(10, farm.deposits(
                    user, 0)['expiryDate'] + 10)
                farm.computeRewards(user, 0, {'from': user})
                farm.computeRewards(user, 0, {'from': user})
                withdraws.append(farm.withdraw(0, {'from': user}))

            farm.getRewardBalance(farm.SPA(), {'from': user})
        if (farm.cooldownPeriod() == 0):
            for i in range(len(setup)):
                farm.computeRewards(user, 0,)

                withdraws.append(farm.withdraw(0, {'from': user}))

            farm.getRewardBalance(farm.SPA(), {'from': user})
