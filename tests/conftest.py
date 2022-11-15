#!/usr/bin/python3
import pytest
import math
import brownie
from brownie import (
    interface,
    Farm,
    chain,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    Contract,


)
import eth_utils


MIN_BALANCE = 1000000000000000000
GAS_LIMIT = 1000000000
NO_LOCKUP_REWARD_RATE = 1*1e18
LOCKUP_REWARD_RATE = 2*1e18

OWNER = '0x6d5240f086637fb408c7F727010A10cf57D51B62'


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


"""Add new farm configurations here to run the tests"""


def approved_rwd_token_list():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        approved_rwd_token_list1 = [
            '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',  # SPA
            '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',  # L2-Dao
            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',  # USDs
            '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',  # Frax
            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',  # USDC
            '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',  # DAI
        ]
        return approved_rwd_token_list1


def test_constants():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        config = {
            'number_of_deposits': 1,
            'funding_data': {
                'spa': 1000000e18,
                'usds': 300000e18,
                'usdc': 100000e6,
            },
            'uniswap_pool_false_data': {
                'token_A':
                '0x5575552988A3A80504bBaeB1311674fCFd40aD4C',
                'token_B':
                '0xD74f5255D557944cf7Dd0E45FF521520002D5747',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
        }
        return config


def constants():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        config = {
            'test_farm_with_lockup': {
                'contract': Farm,
                'config': {
                    'farm_start_time': chain.time()+1000,
                    'cooldown_period': 21,
                    'uniswap_pool_data': {
                        'token_A':
                        '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                        'token_B':
                        '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                        'fee_tier': 3000,
                        'lower_tick': -887220,
                        'upper_tick': 0,
                    },

                    'reward_token_data': [
                        {
                            'reward_tkn':
                            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                            'tkn_manager': OWNER,
                        },
                        # {
                        #     'reward_tkn':
                        #     '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
                        #     'tkn_manager': OWNER,
                        # },
                        {
                            'reward_tkn':
                            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                            'tkn_manager': OWNER,
                        },
                    ],

                }
            },

            'test_farm_without_lockup': {
                'contract': Farm,
                'config': {
                    'farm_start_time': chain.time()+2000,
                    'cooldown_period': 0,

                    'uniswap_pool_data': {
                        'token_A':
                        '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                        'token_B':
                        '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                        'fee_tier': 3000,
                        'lower_tick': -887220,
                        'upper_tick': 0,
                    },

                    'reward_token_data': [
                        {
                            'reward_tkn':
                            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                            'tkn_manager': OWNER,
                        },
                        # {
                        #     'reward_tkn':
                        #     '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                        #     'tkn_manager': OWNER,

                        # },
                        {
                            'reward_tkn':
                            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                            'tkn_manager': OWNER,
                        },
                    ],

                }
            },


        }
        return config


def deploy(owner, contract, config):
    """Deploying the Farm"""
    farm = contract.deploy(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return farm


# def deploy_farm_factory(deployer, fee_receiver, fee_token, fee_amount):
#     """Deploying Farm Factory Proxy Contract"""

#     print('Deploy FarmFactory implementation.')
#     factory_impl = FarmFactory.deploy(
#         {'from': deployer}
#     )
#     print('Deploy Proxy Admin.')
#     proxy_admin = ProxyAdmin.deploy(
#         {'from': deployer, 'gas': GAS_LIMIT})

#     print('Deploy FarmFactory Proxy contract.')
#     proxy = TransparentUpgradeableProxy.deploy(
#         factory_impl.address,
#         proxy_admin.address,
#         eth_utils.to_bytes(hexstr='0x'),
#         {'from': deployer, 'gas_limit': GAS_LIMIT},
#     )
#     factory = Contract.from_abi(
#         'FarmFactory',
#         proxy.address,
#         FarmFactory.abi
#     )
#     print('Initialize FarmFactory proxy contract.')
#     factory.initialize(
#         fee_receiver,
#         fee_token,
#         fee_amount,
#         {'from': deployer}
#     )
#     return factory


def deploy_uni_farm(deployer, contract):
    """Deploying Uniswap Farm Proxy Contract"""

    print('Deploy Uniswap Farm implementation.')
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
        'UniswapFarmV1',
        proxy.address,
        contract.abi
    )
    return uniswap_farm


def init_farm(deployer, farm, config):
    """Init Uniswap Farm Proxy Contract"""
    farm.initialize(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    return farm


def false_init_farm(deployer, farm, config):
    """Init Uniswap Farm Proxy Contract using false params"""
    init = farm.initialize(
        brownie.chain.time()-1,
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    return init


def token_obj(token):
    """Add the token contract interface with the correct address"""
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        token_dict = {
            'spa':
            interface.ERC20('0x5575552988A3A80504bBaeB1311674fCFd40aD4B'),
            'usdc':
            interface.ERC20('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'),
            'usds':
            interface.ERC20('0xD74f5255D557944cf7Dd0E45FF521520002D5748'),
            'usdt':
            interface.ERC20('0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9'),
            'dai':
            interface.ERC20('0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1'),
            'frax':
            interface.ERC20('0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F'),
        }
    return token_dict[token]


def funds(token):
    """"Add the address to be used for funding the user wallet and vault"""
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        fund_dict = {
            'spa': '0xb56e5620a79cfe59af7c0fcae95aadbea8ac32a1',
            'usds': '0x3944b24f768030d41cbcbdcd23cb8b4263290fad',  # STB
            # 'usds': '0x50450351517117cb58189edba6bbad6284d45902',  # 2nd
            'usdc': '0x1714400ff23db4af24f9fd64e7039e6597f18c2b',
            'frax': '0xae0f77c239f72da36d4da20a4bbdaae4ca48e03f'  # frax
        }
    return fund_dict[token]


def fund_account(user, token_name, amount):
    """Function to fund a wallet and approve tokens for vault to spend"""

    token = token_obj(token_name)
    tx = token.transfer(
        user,
        amount,
        {'from': funds(token_name)}
    )
    return tx


@ pytest.fixture(scope='module', autouse=True)
def position_manager():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        position_mgr_address = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'

    position_mgr = brownie.interface.INonfungiblePositionManager(
        position_mgr_address
    )
    return position_mgr


def encode_price(n1, n2):
    return math.trunc(math.sqrt(int(n2)/int(n1)) * 2**96)


def ordered_tokens(token1, amount1, token2, amount2):
    if(token1.address.lower() < token2.address.lower()):
        return token1, amount1, token2, amount2
    return token2, amount2, token1, amount1


def mint_position(
    position_manager,
    token1,
    token2,
    fee,
    lower_tick,
    upper_tick,
    amount1,
    amount2,
    OWNER,
):
    # provide initial liquidity
    t1, a1, t2, a2 = ordered_tokens(token1, amount1, token2, amount2)
    print('Token A: ', t1)
    print('Token A Name: ', t1.name())
    print('Token A Precision: ', t1.decimals())
    print('Amount A: ', a1/(10 ** t1.decimals()))
    print('Token B: ', t2)
    print('Token B Name: ', t2.name())
    print('Token B Precision: ', t2.decimals())
    print('Amount B: ', a2/(10 ** t2.decimals()))

    t1.approve(position_manager.address, a1, {'from': OWNER})
    t2.approve(position_manager.address, a2, {'from': OWNER})
    deadline = 7200 + brownie.chain.time()  # deadline: 2 hours
    params = [
        t1,
        t2,
        fee,
        lower_tick,  # tickLower
        upper_tick,  # tickUpper
        a1,
        a2,
        0,  # minimum amount of spa expected
        0,  # minimum amount of mock_token expected
        OWNER,
        deadline
    ]
    txn = position_manager.mint(
        params,
        {'from': OWNER}
    )
    return txn.events['IncreaseLiquidity']['tokenId']
