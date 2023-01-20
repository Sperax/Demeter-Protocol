from brownie import (
    GaugeController,
    GaugeRewardManager,
    FarmFactory,
    Demeter_UniV3Farm_v2,
    network,
    chain,
    interface,
    Contract,
    accounts
)

from .constants import vespa_constants

OWNER = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
WEEK = 604800


def token_obj(token):
    """Add the token contract interface with the correct address"""
    if (network.show_active() == 'arbitrum-main-fork'):
        token_dict = {
            'spa':
            interface.ERC20('0x5575552988A3A80504bBaeB1311674fCFd40aD4B'),
            'usdc':
            interface.ERC20('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'),
            'usds':
            interface.ERC20('0xD74f5255D557944cf7Dd0E45FF521520002D5748'),
            'usdt':
            interface.ERC20('0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9'),
            'dai':
            interface.ERC20('0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1'),
            'frax':
            interface.ERC20('0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F'),
        }
    return token_dict[token]


def funds(token):
    """"Add the address to be used for funding the user wallet and vault"""
    if (network.show_active() == 'arbitrum-main-fork'):
        fund_dict = {
            'spa': '0xb56e5620a79cfe59af7c0fcae95aadbea8ac32a1',
            'usds': '0x3944b24f768030d41cbcbdcd23cb8b4263290fad',  # STB
            # 'usds': '0x50450351517117cb58189edba6bbad6284d45902',  # 2nd
            'usdc': '0x62383739d68dd0f844103db8dfb05a7eded5bbe6',
            'frax': '0xae0f77c239f72da36d4da20a4bbdaae4ca48e03f'  # frax
        }
    return fund_dict[token]


def fund_account(user, token_name, amount):
    """Function to fund a wallet and approve tokens for vault to spend"""
    token = token_obj(token_name)
    tx = token.transfer(
        user,
        amount,
        {'from': funds(token_name)}
    )
    return tx


def main():
    user = str(input('Enter user wallet address: '))
    gauge_controller = GaugeController.deploy(
        vespa_constants[network.show_active()]['veSPA'],
        {'from': OWNER}
    )

    vespa = Contract.from_abi(  # noqa
        'vespa',
        vespa_constants[network.show_active()]['veSPA'],
        interface.IveSPA.abi
    )
    reward_manager = GaugeRewardManager.deploy(  # noqa
        1e24,
        7000,
        gauge_controller,
        OWNER,
        {'from': OWNER}
    )
    farm_factory = Contract.from_abi(
        'farm_factory',
        '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
        FarmFactory.abi
    )
    farms = farm_factory.getFarmList()

    print('Adding Gauge type')
    _ = gauge_controller.addType('DemeterFarm', 1, {'from': OWNER})

    print('Adding Gauges:')
    c = 3
    for farm in farms:
        if (c == 0):
            break
        farm = Demeter_UniV3Farm_v2.at(farm)
        if not farm.isClosed():
            _ = gauge_controller.addGauge(farm, 0, 0, {'from': OWNER})
        c -= 1

    print('Checking veSPA stats:')
    user_vespa_bal = vespa.balanceOf(user)
    print(f'User veSPA bal: {user_vespa_bal}')
    print(f'Total veSPA bal: {vespa.totalSupply()}')

    print('Funding user wallet')
    spa = token_obj('spa')
    fund_account(user, 'spa', 1e24)
    accounts[0].transfer(user, 1e19)
    print(f'user SPA balance: {spa.balanceOf(user)}')
    chain.snapshot()
