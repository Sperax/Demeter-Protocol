from brownie import (
    Farm,
    chain,
    accounts
)

constants = {
    'test_farm_with_lockup': {
        'contract': Farm,
        'config': {
            'farm_start_time': chain.time() + (86400 * 1),
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
                   'reward_tkn': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                   'tkn_manager': accounts[0].address,
                   'emergency_r': accounts[1].address,
                   'reward_rate': [1e13, 5e12],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': accounts[0].address,
                   'emergency_r': accounts[1].address,
                   'reward_rate': [1e15, 5e14],
                },
            ]
        }
    },
    'test_farm_without_lockup': {
        'contract': Farm,
        'config': {
            'farm_start_time': chain.time() + (86400 * 1),
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
                   'reward_tkn': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                   'tkn_manager': accounts[0].address,
                   'emergency_r': accounts[1].address,
                   'reward_rate': [1e13],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': accounts[0].address,
                   'emergency_r': accounts[1].address,
                   'reward_rate': [1e15],
                },
            ]
        }
    }
}
