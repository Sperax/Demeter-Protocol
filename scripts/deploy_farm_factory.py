from brownie import (
    Contract,
    network,
    ProxyAdmin,
    TransparentUpgradeableProxy,
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
import eth_utils
from .constants import factory_constants

GAS_LIMIT = 80000000
MULTI_SIG = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
ADMIN = '0xEeE35407BC8eAF4D82A7CD4876f87dD0De2f07B8'


def deploy(deployer, contract, config):
    print(f'\ncontract deployer account: {deployer.address}\n')
    print(json.dumps(config, indent=4))
    confirm('Are the above configurations correct?')

    print('Deploying FarmFactory implementation:')
    factory_impl = contract.deploy(
        {'from': deployer, 'gas_limit': GAS_LIMIT}
    )

    # Deploy the proxy admin contract
    print('Deploying ProxyAdmin:')
    proxy_admin = ProxyAdmin.deploy(
        {'from': deployer, 'gas_limit': GAS_LIMIT}
    )

    print('Deploying FarmFactory proxy:')
    proxy = TransparentUpgradeableProxy.deploy(
        factory_impl.address,
        proxy_admin.address,
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    factory = Contract.from_abi(
        'FarmFactory',
        proxy.address,
        contract.abi
    )

    print('Initializing proxy contract:')
    factory.initialize(
        config['fee_receiver'],
        config['fee_token'],
        config['fee_amount'],
        {'from': deployer}
    )

    print('Transferring ownership to MULTI_SIG:')
    factory.transferOwnership(MULTI_SIG, {
        'from': deployer
    })

    print('Transferring admin ownership to ADMIN:')
    proxy_admin.transferOwnership(ADMIN, {
        'from': deployer
    })

    return {
        'factory_implementation': factory_impl.address,
        'proxy_admin': proxy_admin.address,
        'factory_proxy': proxy.address,
    }


def main():
    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    deployer = get_account('deployer account')
    config_name, contract, config = get_config(
        'Select farm_factory config:',
        factory_constants
    )

    deployments = deploy(deployer, contract, config)

    print(f'\n{network.show_active()}:\n')
    print(f'{config_name} deployment addresses:')
    print(json.dumps(deployments, indent=4))

    data = dict(
        type='deployment_'+config_name,
        config=config,
        deployer=deployer.address,
        owner=MULTI_SIG,
        deployments=deployments
    )

    print(json.dumps(data, indent=4))

    save_deployment_artifacts(data, config_name)
