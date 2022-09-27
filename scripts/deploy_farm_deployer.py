from brownie import (
    network,
    FarmFactory
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
from .constants import farm_deployer_constants

GAS_LIMIT = 80000000


def deploy(deployer, contract, config):
    print(f'\ncontract deployer account: {deployer.address}\n')
    print(json.dumps(config, indent=4))
    confirm('Are the above configurations correct?')

    factory = config['farm_factory']
    
    print('Deploy UniswapFarmV1Deployer contract.')
    farm_deployer = contract.deploy(factory, {'from': deployer})

    # TODO To be done manually
    # print('Register the deployer contract with the Factory.')
    # factory.registerFarmDeployer(
    #     farm_deployer,
    #     {'from': MULTISIG, 'gas_limit': GAS_LIMIT}
    # )

    return {
        'farm_deployer': farm_deployer.address,
    }


def main():
    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    deployer = get_account('deployer account')
    config_name, contract, config = get_config(
        'Select farm_factory config:',
        farm_deployer_constants
    )

    deployments = deploy(deployer, contract, config)

    print(f'\n{network.show_active()}:\n')
    print(f'{config_name} deployment addresses:')
    print(json.dumps(deployments, indent=4))

    data = dict(
        type='deployment_'+config_name,
        config=config,
        deployer=deployer.address,
        deployments=deployments
    )

    print(json.dumps(data, indent=4))

    save_deployment_artifacts(data, config_name)
