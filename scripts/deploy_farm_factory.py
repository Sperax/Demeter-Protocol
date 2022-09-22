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
from .constants import factory_constants, approved_rwd_token_list1

GAS_LIMIT = 80000000
MULTI_SIG = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'


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

    print('Approving reward tokens')
    factory.approveRewardTokens(approved_rwd_token_list1)

    return {
        'factory_implementation': factory_impl.address,
        'proxy_admin': proxy_admin.address,
        'factory_proxy': proxy.address,
        'factory': factory.address,
    }


def main():
    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    owner = get_account('owner account')
    config_name, contract, config = get_config(
        'Select farm_factory config:',
        factory_constants
    )

    deployments = deploy(owner, contract, config)

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
