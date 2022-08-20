from brownie import (
    Farm,
    chain,
    accounts
)

constants = {
    'l2dao_usds': {
        'contract': Farm,
        'config': {
            'farm_start_time': chain.time() + (86400 * 1),
            'cooldown_period': 0,
            'uniswap_pool_data': {
                'token_A': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_tier': 3000,
                'lower_tick': -48960,
                'upper_tick': -6900,
            },
            'reward_token_data': [
                {
                   'reward_tkn': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                   'tkn_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'reward_rate': [6.4295e16],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'reward_rate': [3.8580e17],
                },
            ]
        }
    },
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
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'reward_rate': [1e13, 5e12],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': accounts[0].address,
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
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
