import signal
from brownie import (
    network,
)
from .utils import (
    confirm,
    get_account,
    get_config,
    save_deployment_artifacts,
    signal_handler
)
import json

GAS_LIMIT = 100000000


def deploy(owner, contract, config):
    print(f'\ncontract owner account: {owner.address}\n')
    print(json.dumps(config, indent=4))
    confirm('Are the above configurations correct?')
    farm = contract.deploy(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['uniswap_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return farm


def main():
    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    owner = get_account('owner account')
    config_name, contract, config = get_config('Select farm config:')

    farm = deploy(owner, contract, config)

    print(f'\n{network.show_active()}:\n')
    print(f'{config_name} Farm address: {farm.address}')

    data = dict(
        type='deployment_'+config_name+'_farm',
        config=config,
        owner=owner.address
    )
    data[config_name+'_farm'] = farm.address
    print(json.dumps(data, indent=4))

    save_deployment_artifacts(data)
