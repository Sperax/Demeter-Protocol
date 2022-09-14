#!/usr/bin/python3
import pytest
import math
import brownie
from brownie import (
    interface,
    Farm,
    chain,

)


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
            'farm_start_time': chain.time(),
            'cooldown_period': 86400 * 21,
            'uniswap_pool_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'reward_token_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                    'emergency_r':
                    '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                    'reward_rate': [1e13, 5e12],
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,
                    'emergency_r':
                    '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                    'reward_rate': [1e15, 5e14],
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
            'farm_start_time': chain.time(),
            'cooldown_period': 0,
            'uniswap_pool_data': {
                'token_A': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'lower_tick': -887220,
                'upper_tick': 0,
            },
            'reward_token_data': [
                {
                    'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': owner,
                    'emergency_r':
                    '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                    'reward_rate': [1e13],
                },
                {
                    'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': owner,
                    'emergency_r':
                    '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                    'reward_rate': [1e15],
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


def token_obj(token):
    """Add the token contract interface with the correct address"""
    token_dict = {
        'spa': interface.ERC20('0x5575552988A3A80504bBaeB1311674fCFd40aD4B'),
        'usdc': interface.ERC20('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'),
        'usds': interface.ERC20('0xD74f5255D557944cf7Dd0E45FF521520002D5748'),
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
