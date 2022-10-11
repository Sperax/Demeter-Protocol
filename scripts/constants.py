from brownie import (
    Farm,
    FarmFactory,
    UniswapFarmV1Deployer,
    chain,
)

factory_constants = {
    'FarmFactory_v1': {
        'contract': FarmFactory,
        'config': {
            'fee_receiver': '0x4F987B24bD2194a574bB3F57b4e66B7f7eD36196',
            'fee_token': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
            'fee_amount': 500e18
        }
    }
}

farm_deployer_constants = {
    'UniswapFarmV1_deployer': {
        'contract': UniswapFarmV1Deployer,
        'config': {
            'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
        }
    }
}

demeter_farm_constants = {
    'l2dao_usds': {
        'contract': UniswapFarmV1Deployer,
        'config': {
            'deployer': '',
            'farm_admin': '',
            'farm_start_time': chain.time(),
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
                },
                {
                    'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                },
            ]
        }
    },
}

old_farm_constants = {
    'l2dao_usds': {
        'contract': Farm,
        'config': {
            'farm_start_time': chain.time(),
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
                   'tkn_manager': '0x6d5240f086637fb408c7F727010A10cf57D51B62',
                   'emergency_r': '0x5318f07A3a20A2f8bb0DDf14F1DD58C517a76508', #  L2DAO reserve # noqa
                   'reward_rate': [6.4295e16],
                },
                {
                   'reward_tkn': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                   'tkn_manager': '0x6d5240f086637fb408c7F727010A10cf57D51B62',
                   'emergency_r': '0xb56e5620A79cfe59aF7c0FcaE95aADbEA8ac32A1',
                   'reward_rate': [3.8580e17],
                },
            ]
        }
    },
}
