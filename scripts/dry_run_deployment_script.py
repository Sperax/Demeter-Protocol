from brownie import (
    accounts,
    Contract,
    chain,
    UniswapFarmV1,
    UniswapFarmV1Deployer,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    FarmFactory
)
import eth_utils
from .constants import approved_rwd_token_list1
GAS_LIMIT = 80000000


def main():
    deployer = accounts[0]

    print('Deploy FarmFactory implementation.')
    factory_impl = FarmFactory.deploy(
        {'from': deployer}
    )

    print('Deploy Proxy Admin.')
    # Deploy the proxy admin contract
    proxy_admin = ProxyAdmin.deploy(
        {'from': deployer, 'gas': GAS_LIMIT}
    )

    print('Deploy FarmFactory Proxy contract.')
    proxy = TransparentUpgradeableProxy.deploy(
        factory_impl.address,
        proxy_admin.address,
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    factory = Contract.from_abi(
        'FarmFactory',
        proxy.address,
        FarmFactory.abi
    )

    print('Initialize FarmFactory proxy contract.')
    factory.initialize(
        '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
        '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
        500e18,
        {'from': deployer}
    )

    print('Approving rewardTokens.')
    factory.approveRewardTokens(approved_rwd_token_list1, {'from': deployer})

    print('Deploy UniswapFarmV1Deployer contract.')
    farm_deployer = UniswapFarmV1Deployer.deploy(factory, {'from': deployer})

    print('Register the deployer contract with the Factory.')
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )

    print('Create a UniswapV3 Farm using the deployer.')

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
                'token_manager': '0x5b12d9846F8612E439730d18E1C12634753B1bF1'
            }
        ]
    }
    create_tx = farm_deployer.createFarm(
        (
            config['farm_admin'],
            config['farm_start_time'],
            config['cooldown_period'],
            list(config['uniswap_pool_data'].values()),
            list(map(lambda x: list(x.values()), config['reward_token_data'])),
        ),
        {'from': deployer}
    )

    # Initialize contract objects
    farm_implementation = UniswapFarmV1.at(farm_deployer.farmImplementation())  # noqa
    farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
