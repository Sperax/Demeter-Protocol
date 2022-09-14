#!/usr/bin/python3
import pytest
import math
import brownie
from brownie import (
    interface,
    Farm,
    UniswapFarmV1,
    chain,
    TransparentUpgradeableProxy,
    Contract,

)
import eth_utils


MIN_BALANCE = 1000000000000000000
GAS_LIMIT = 1000000000
NO_LOCKUP_REWARD_RATE = 1*1e18
LOCKUP_REWARD_RATE = 2*1e18

owner = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'

"""Add new farm configurations here to run the tests"""

constants = {
    'test_farm_with_lockup': {
        'contract': Farm,
        'token_A': 'spa',
        'token_B': 'usds',
        'reward_token_A': 'usds',
        'reward_token_B': 'spa',
        'reward_tokens': ['usds', 'spa'],
        'config': {
            'farm_start_time': chain.time()+1000,
            'cooldown_period': 86400 * 21,
            'uniswap_pool_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'uniswap_pool_false_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4C',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5747',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'reward_token_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,
                },
            ],
            'reward_token_over_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',
                    'tkn_manager': owner,
                },
            ]

        }
    },

    'test_farm_without_lockup': {
        'contract': Farm,
        'token_A': 'spa',
        'token_B': 'usds',
        'reward_token_A': 'usds',
        'reward_token_B': 'spa',
        'reward_tokens': ['usds', 'spa'],
        'config': {
            'farm_start_time': chain.time()+1000,
            'cooldown_period': 0,
            'uniswap_pool_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'uniswap_pool_false_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4C',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5747',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'reward_token_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,

                },
            ],
            'reward_token_over_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,
                },

            ]

        }
    },


}


def deploy(owner, contract, config):
    farm = contract.deploy(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return farm


def deploy_uni_farm(owner, contract):
    farm = contract.deploy(

        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    proxy = TransparentUpgradeableProxy.deploy(
        farm.address,
        '0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25',
        eth_utils.to_bytes(hexstr='0x'),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )

    factory = Contract.from_abi(
        'uniswapFarmV1',
        proxy.address,
        contract.abi
    )
    return factory


def init_farm(owner, farm, config):
    init = farm.initialize(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return init


def false_init_farm(owner, farm, config):
    init = farm.initialize(
        brownie.chain.time()-1,
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return init


def token_obj(token):
    """Add the token contract interface with the correct address"""
    token_dict = {
        'spa': interface.ERC20('0x5575552988A3A80504bBaeB1311674fCFd40aD4B'),
        'usdc': interface.ERC20('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'),
        'usds': interface.ERC20('0xD74f5255D557944cf7Dd0E45FF521520002D5748'),
        'usdt': interface.ERC20('0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9'),
        'dai': interface.ERC20('0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1'),
        'frax': interface.ERC20('0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F'),
    }
    return token_dict[token]


def funds(token):
    """"Add the address to be used for funding the user wallet and vault"""
    fund_dict = {
        'spa': '0xb56e5620a79cfe59af7c0fcae95aadbea8ac32a1',
        'usds': '0x3944b24f768030d41cbcbdcd23cb8b4263290fad',  # streetbeat
        'usdc': '0x1714400ff23db4af24f9fd64e7039e6597f18c2b'
    }
    return fund_dict[token]


def fund_account(user, token_name, amount):
    """Function to fund a wallet and approve tokens for vault to spend"""

    token = token_obj(token_name)
    token.transfer(
        user,
        amount,
        {'from': funds(token_name)}
    )


@pytest.fixture(scope='module', autouse=True)
def position_manager():
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
    owner,
):
    # provide initial liquidity
    t1, a1, t2, a2 = ordered_tokens(token1, amount1, token2, amount2)
    print('t1: ', t1)
    print('a1: ', a1)
    print('t2: ', t2)
    print('a2: ', a2)

    t1.approve(position_manager.address, a1, {'from': owner})
    t2.approve(position_manager.address, a2, {'from': owner})
    deadline = 1637632800 + brownie.chain.time()  # deadline: 2 hours
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
        owner,
        deadline
    ]
    txn = position_manager.mint(
        params,
        {'from': owner}
    )
    return txn.events['IncreaseLiquidity']['tokenId']
