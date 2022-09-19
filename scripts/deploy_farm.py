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
import signal
import json
from .constants import demeter_farm_constants

GAS_LIMIT = 80000000


def create_farm(deployer, contract, config):
    print(f'\ncontract deployer account: {deployer.address}\n')
    print(json.dumps(config, indent=4))
    confirm('Are the above configurations correct?')

    farm_deployer = contract.at(config['deployer'])

    print('Create farm  contract.')
    create_tx = farm_deployer.createFarm(
            config['farm_admin'],
            config['farm_start_time'],
            config['cooldown_period'],
            list(config['uniswap_pool_data'].values()),
            list(map(lambda x: list(x.values()), config['reward_token_data'])),
            {'from': deployer}
        )

    return {
        'farm': create_tx.new_contracts[0],
    }


def main():
    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    owner = get_account('owner account')
    config_name, contract, config = get_config(
        'Select farm config:',
        demeter_farm_constants
    )

    deployments = create_farm(owner, contract, config)

    print(f'\n{network.show_active()}:\n')
    print(f'{config_name} deployment addresses:')
    print(json.dumps(deployments, indent=4))

    data = dict(
        type='deployment_'+config_name,
        config=config,
        owner=owner.address
    )

    print(json.dumps(data, indent=4))

    save_deployment_artifacts(data, config_name)
