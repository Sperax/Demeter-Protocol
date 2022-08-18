import signal
from brownie import (
    network,
    accounts,
    chain,
    Contract,
    interface,
)
from scripts.deploy import deploy
from .utils import (
    get_config,
    signal_handler
)
import json

GAS_LIMIT = 1000000000


def print_stats(farm, user_account, deposit_id):
    print('\nFarm stats: ')
    print('LastFundUpdateTime: ', farm.lastFundUpdateTime())
    print('CommonFund: ')
    print(
        json.dumps(
            farm.getRewardFundInfo(0).dict(),
            indent=4
        )
    )
    print('LockupFund: ')
    print(
        json.dumps(
            farm.getRewardFundInfo(1).dict(),
            indent=4
        )
    )

    num_deposit = farm.getNumDeposits(user_account)

    if(num_deposit > 0 and deposit_id < num_deposit):
        print('User deposit: ')
        deposit = farm.getDeposit(user_account, deposit_id).dict()
        print(json.dumps(deposit, sort_keys=True, indent=4))

        print('\nDeposit subscription: ')
        n = farm.getNumSubscriptions(deposit['tokenId'])
        for i in range(n):
            print(
                json.dumps(
                    farm.getSubscriptionInfo(deposit['tokenId'], i).dict(),
                    sort_keys=True,
                    indent=4
                )
            )


def addr_to_token(addr):
    name_dict = {
        '0x5575552988A3A80504bBaeB1311674fCFd40aD4B': 'spa',
        '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8': 'usdc',
        '0xD74f5255D557944cf7Dd0E45FF521520002D5748': 'usds',
        '0x2CaB3abfC1670D1a452dF502e216a66883cDf079': 'l2dao',
    }
    return name_dict[addr]


def token_obj(token):
    """Add the token contract interface with the correct address"""
    if('0x' in token):
        token = addr_to_token(token)

    token_dict = {
        'spa': interface.ERC20('0x5575552988A3A80504bBaeB1311674fCFd40aD4B'),
        'usdc': interface.ERC20('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'),
        'usds': interface.ERC20('0xD74f5255D557944cf7Dd0E45FF521520002D5748'),
        'l2dao': interface.ERC20(
            '0x2CaB3abfC1670D1a452dF502e216a66883cDf079'
        ),
    }
    return token_dict[token]


def funds(token):
    """"Add the address to be used for funding the user wallet and vault"""
    if('0x' in token):
        token = addr_to_token(token)
    fund_dict = {
        'spa': '0xda7ed5d425640c96dc52cc5fae8218f99450df95',
        'usds': '0x3944b24f768030d41cbcbdcd23cb8b4263290fad',
        'usdc': '0x1714400ff23db4af24f9fd64e7039e6597f18c2b',
        'l2dao': '0x5318f07a3a20a2f8bb0ddf14f1dd58c517a76508'
    }
    return fund_dict[token]


def fund_account(user, token, amount):
    """Function to fund a wallet and approve tokens for vault to spend"""
    token_name = token
    if(hasattr(token, 'address')):
        token_name = token.address
    else:
        token = token_obj(token)
    token.transfer(user, amount, {'from': funds(token_name)})


def main():
    owner = accounts[0]

    user_account = input('Enter your metamask wallet address: ')
    use_pre_deployed = input('Use pre-deployed contract? (y/n): ')

    # handle ctrl-C event
    signal.signal(signal.SIGINT, signal_handler)

    # contract owner account
    farm = ''
    config_name, contract, config = get_config('Select farm config:')
    if(use_pre_deployed == 'n'):
        farm = deploy(owner, contract, config)
    else:
        # 0x84f7F3246fD8beAAc8Af4aB08a2161506Cb97174
        farm_address = input('Enter farm address: ')
        farm = Contract.from_abi(
            config_name,
            farm_address,
            contract.abi
        )

    print(f'\n{network.show_active()}:\n')
    print(f'{config_name} Farm address: {farm.address}')
    reward_data = list(
        map(lambda x: list(x.values()), config['reward_token_data'])
    ),
    token_A = token_obj(config['uniswap_pool_data']['token_A'])
    token_B = token_obj(config['uniswap_pool_data']['token_B'])
    rwd_tokens = map(lambda x: token_obj(x[0][0]), reward_data)

    accounts[0].transfer(user_account, '50 ether')

    for token in rwd_tokens:
        fund_account(owner, token, 2e23)
        token.approve(farm, 1e6 * 10**token.decimals(), {'from': owner})
        farm.addRewards(token, 1e5 * 10**token.decimals(), {'from': owner})

    fund_account(user_account, token_A, 1e4 * 10 ** token_A.decimals())
    fund_account(user_account, token_B, 1e4 * 10 ** token_B.decimals())

    chain.snapshot()
