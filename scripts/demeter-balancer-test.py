from brownie import (
    Demeter_BalancerFarm_Deployer,
    chain,
    interface
)

factory = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
balancerVault = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
OWNER = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
USDs = '0xD74f5255D557944cf7Dd0E45FF521520002D5748'
usdsFunder = '0x25af636b72f9e1f63b18de140d4b568c3891d295'


def createFarm(farmDeployer):
    creator = input('Enter user\'s address: ')
    params = {
        'farm-admin': OWNER,
        'farm-start-time': chain.time() + 120,
        'cooldown-period': 0,
        'pool-id': '0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd',  # noqa
        'reward-token-data': []
    }
    interface.ERC20(USDs).transfer(creator, 100e18, {'from': usdsFunder})
    interface.ERC20(USDs).approve(farmDeployer, 100e18, {'from': creator})
    interface.IFarmFactory(factory).registerFarmDeployer(
        farmDeployer, {'from': OWNER}
    )
    tx = farmDeployer.createFarm([
        params['farm-admin'],
        params['farm-start-time'],
        params['cooldown-period'],
        params['pool-id'],
        params['reward-token-data']],
        {'from': creator}
    )
    return tx


def main():
    farmDeployer = Demeter_BalancerFarm_Deployer.deploy(
        factory,
        balancerVault,
        'Demeter Balancer Deployer',
        {'from': OWNER}
    )
    print('Demeter balancer farm deployer deployed', farmDeployer)
    print('Creating farm ...')
    tx = createFarm(farmDeployer)
    print(tx.events)
