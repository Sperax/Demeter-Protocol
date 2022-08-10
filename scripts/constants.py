from brownie import (
    Farm,
    chain
)

constants = {
    'dummy_name': {
        'contract': Farm,
        'config': {
            'farm_start_time': chain.time() + (86400 * 2),
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
                   'tkn_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'reward_rate': [7716*1e14, 3858*1e14],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'emergency_r': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                   'reward_rate': [7716*1e14, 3858*1e14],
                },
            ]
        }
    }
}
