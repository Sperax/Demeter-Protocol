#!/usr/bin/python3
import pytest
import math
import brownie
from brownie import (
    interface,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    Contract,
    Demeter_CamelotFarm,
    Demeter_CamelotFarm_Deployer,
    accounts

)
import sys
import eth_utils
sys.path.append('../scripts')


MIN_BALANCE = 1000000000000000000
GAS_LIMIT = 1000000000
NO_LOCKUP_REWARD_RATE = 1*1e18
LOCKUP_REWARD_RATE = 2*1e18

OWNER = '0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188'
DEMETER_FACTORY = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
CAMELOT_FACTORY = '0x6EcCab422D763aC031210895C81787E87B43A652'
CAMELOT_NFT_FACTORY = '0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d'
CAMELOT_POSITION_HELPER = '0xe458018Ad4283C90fB7F5460e24C4016F81b8175'
deployer = brownie.accounts
USDs_Owner = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'


def check_function(farm, func_name):
    for key in farm.selectors:
        if func_name == farm.selectors[key]:
            return True
    return False


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


"""Add new farm configurations here to run the tests"""


def approved_rwd_token_list():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        approved_rwd_token_list1 = [
            '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',  # SPA
            '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',  # L2-Dao
            '0xD74f5255D557944cf7Dd0E45FF521520002D5748',  # USDs
            '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',  # Frax
            '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',  # USDC
            '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',  # DAI
        ]
        return approved_rwd_token_list1


def test_constants():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        config = {
            'number_of_deposits': 2,
            'funding_data': {
                'spa': 100000e18,
                'usds': 10000e18,
                'usdc': 100000e6,
            },
            'camelot_pool_false_data': {
                'token_A':
                '0x5575552988A3A80504bBaeB1311674fCFd40aD4C',
                'token_B':
                '0xD74f5255D557944cf7Dd0E45FF521520002D5747',
            },
        }
        return config


def deploy(owner, contract, config):
    """Deploying the Farm"""
    farm = contract.deploy(
        config['farm_start_time'],
        config['cooldown_period'],
        list(config['camelot_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    return farm


def deploy_farm_deployer(deployer, contract):
    """Deploying farm deployer Proxy Contract"""

    print('Deploy farm deployer implementation.')
    farm = contract.deploy(
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    print('Deploy Proxy Admin farm deployer.')
    # Deploy the proxy admin contract
    proxy_admin = ProxyAdmin.deploy(
        {'from': deployer, 'gas': GAS_LIMIT})

    proxy = TransparentUpgradeableProxy.deploy(
        farm.address,
        proxy_admin.address,
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    farm_deployer = Contract.from_abi(
        'Demeter_UniswapV3FarmDeployer_v2',
        proxy.address,
        contract.abi
    )
    return farm_deployer


def create_deployer_farm(deployer, farm_deployer, config):
    """Init Uniswap Farm Proxy Contract"""
    usds = token_obj('usds')

    _ = usds.transfer(
        deployer.address,
        1000*10e18,
        {'from': funds('usds')}
    )
    _ = usds.approve(farm_deployer, 1000e18, {'from': deployer})
    create_tx = farm_deployer.createFarm(
        (
            config['admin'],
            config['farm_start_time'],
            config['cooldown_period'],
            list(
                config['camelot_pool_data'].values()),
            list(
                map(lambda x: list(x.values()), config['reward_token_data'])),
        ),
        {'from': deployer.address},
    )
    return Demeter_CamelotFarm.at(create_tx.new_contracts[0])


def create_deployer_farm_e20(deployer, farm_deployer, config, factory):
    user_deployer = accounts[1]
    """Init Uniswap Farm Proxy Contract"""
    usds = token_obj('usds')

    _ = usds.transfer(
        user_deployer,
        10000*1e18,
        {'from': funds('usds')}
    )

    _ = usds.approve(farm_deployer, 100000*1e18, {'from': user_deployer})

    create_tx = farm_deployer.createFarm(
        (
            config['admin'],
            config['farm_start_time'],
            config['cooldown_period'],
            list(
                config['camelot_pool_data'].values()),
            list(
                map(lambda x: list(x.values()), config['reward_token_data'])),
        ),
        {'from': user_deployer.address},
    )
    return Demeter_CamelotFarm_Deployer.at(create_tx.new_contracts[0])


def false_init_farm(deployer, farm, config):
    """Init Uniswap Farm Proxy Contract using false params"""
    init = farm.initialize(
        brownie.chain.time()-1,
        config['cooldown_period'],
        list(config['camelot_pool_data'].values()),
        list(map(lambda x: list(x.values()), config['reward_token_data'])),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )
    return init


def token_obj(token):
    """Add the token contract interface with the correct address"""
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
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
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        fund_dict = {
            'spa': '0xb56e5620a79cfe59af7c0fcae95aadbea8ac32a1',
            'usds': '0xf2839e0b30b5e96083085f498b14bbc12530b734',
            # 'usds': '0x50450351517117cb58189edba6bbad6284d45902',
            'usdc': '0x62383739d68dd0f844103db8dfb05a7eded5bbe6',
            'frax': '0x5a9bef8cea603aac78a523fb245c1a9264d50706',
            'Camelot-LP': '0x85054ed5a0722117deee9411f2f1ef780cc97056'
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


@ pytest.fixture(scope='module', autouse=True)
def pm():
    if (brownie.network.show_active() == 'arbitrum-main-fork'):
        position_mgr_address = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'

    position_mgr = brownie.interface.INonfungiblePositionManager(
        position_mgr_address
    )
    return position_mgr


def encode_price(n1, n2):
    return math.trunc(math.sqrt(int(n2)/int(n1)) * 2**96)


def ordered_tokens(token1, amount1, token2, amount2):
    if(token1.address.lower() < token2.address.lower()):
        return token1, amount1, token2, amount2
    return token2, amount2, token1, amount1


def get_lp_token(token1, token2):
    camelot_factory = Contract.from_abi(
        'Camelot factory',
        CAMELOT_FACTORY,
        interface.ICamelotFactory.abi
    )
    lp_token = camelot_factory.getPair(token1, token2)
    nft_pool_factory = Contract.from_abi(
        'Camelot: NFTpoolFactory',
        CAMELOT_NFT_FACTORY,
        interface.INFTPoolFactory.abi
    )
    nft_pool_addr = nft_pool_factory.getPool(lp_token)

    pool = interface.INFTPool(nft_pool_addr)
    return lp_token, nft_pool_addr, pool


def mint_position(
    token1,
    token2,
    amount1,
    amount2,
    deposit_index,
    user,

):
    # provide initial liquidity

    position_helper = Contract.from_abi(
        'PositionHelper',
        CAMELOT_POSITION_HELPER,
        interface.IPositionHelper.abi
    )
    t1, a1, t2, a2 = ordered_tokens(token1, amount1, token2, amount2)
    _, nft_pool_addr, pool = get_lp_token(token1, token2)
    print('pool address is:', nft_pool_addr)
    print('Token A: ', t1)
    print('Token A Name: ', t1.name())
    print('Token A Precision: ', t1.decimals())
    print('Amount A: ', a1/(10 ** t1.decimals()))
    print('Token B: ', t2)
    print('Token B Name: ', t2.name())
    print('Token B Precision: ', t2.decimals())
    print('Amount B: ', a2/(10 ** t2.decimals()))

    t1.approve(position_helper, a1, {'from': user})
    t2.approve(position_helper, a2, {'from': user})
    deadline = 7200 + brownie.chain.time()  # deadline: 2 hours
    _ = position_helper.addLiquidityAndCreatePosition(
        t1,
        t2,
        a1,
        a2,
        0,  # minimum amount of token1 expected
        0,  # minimum amount of token2 expected
        deadline,
        user,
        nft_pool_addr,
        0,
        {'from': user}
    )

    token_id = pool.tokenOfOwnerByIndex(user, deposit_index)
    return token_id
