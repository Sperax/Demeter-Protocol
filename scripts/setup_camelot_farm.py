from brownie import (
    Demeter_CamelotFarm,
    Demeter_CamelotFarm_Deployer,
    Demeter_UniV3FarmDeployer_v2,
    FarmFactory,
    chain,
    interface,
    Contract
)

from ..tests.conftest import (
    fund_account,
    token_obj,
)

from .constants import (
    Create_Farm_data,
    Farm_config
)

OWNER = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
DEMETER_FACTORY = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
CAMELOT_FACTORY = '0x6EcCab422D763aC031210895C81787E87B43A652'
CAMELOT_NFT_FACTORY = '0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d'
CAMELOT_POSITION_HELPER = '0xe458018Ad4283C90fB7F5460e24C4016F81b8175'


def create_farm(config: Create_Farm_data, farm_deployer, user):
    conf = config.config
    tx = farm_deployer.createFarm(
        [
            conf.deployment_params['farm_admin'],
            conf.deployment_params['farm_start_time'],
            conf.deployment_params['cooldown_period'],
            list(conf.deployment_params['pool_data'].values()),
            list(
                map(
                    lambda x: list(x.values()),
                    conf.deployment_params['reward_token_data']
                )
            )
        ],
        {'from': user}
    )
    return config.contract.at(tx.new_contracts[0])


def main():
    user = str(input('Enter user wallet address: '))
    usds = token_obj('usds')
    spa = token_obj('spa')

    fund_account(user, 'spa', 1e23)
    fund_account(user, 'usds', 1e23)

    deployer = Demeter_CamelotFarm_Deployer.deploy(
        DEMETER_FACTORY,
        CAMELOT_FACTORY,
        {'from': OWNER}
    )

    uniV3_deployer = Demeter_UniV3FarmDeployer_v2.deploy(
        DEMETER_FACTORY,
        {'from': OWNER}
    )

    farm_factory = FarmFactory.at(DEMETER_FACTORY)

    farm_factory.removeDeployer(0, {'from': OWNER})
    farm_factory.registerFarmDeployer(uniV3_deployer, {'from': OWNER})
    farm_factory.registerFarmDeployer(deployer, {'from': OWNER})

    farm_config = Create_Farm_data(
        contract=Demeter_CamelotFarm,
        deployer_contract=Demeter_CamelotFarm_Deployer,
        deployer_address=deployer,
        config=Farm_config(
            deployment_params={
                'farm_admin': user,
                'farm_start_time': chain.time() + 100,
                'cooldown_period': 0,
                'pool_data': {
                    'token_A': spa,
                    'token_B': usds,
                },
                'reward_token_data': []
            }
        )
    )

    position_helper = Contract.from_abi(
        'PositionHelper',
        CAMELOT_POSITION_HELPER,
        interface.IPositionHelper.abi
    )

    camelot_factory = Contract.from_abi(
        'Camelot factory',
        CAMELOT_FACTORY,
        interface.ICamelotFactory.abi
    )

    lp_token = camelot_factory.getPair(usds, spa)

    nft_pool_factory = Contract.from_abi(
        'Camelot: NFTpoolFactory',
        CAMELOT_NFT_FACTORY,
        interface.INFTPoolFactory.abi
    )

    nft_pool_addr = nft_pool_factory.getPool(lp_token)
    pool = interface.INFTPool(nft_pool_addr)

    usds.approve(deployer, 1e21, {'from': user})
    farm = create_farm(farm_config, deployer, user)

    spa.approve(position_helper, 1e24, {'from': user})
    usds.approve(position_helper, 1e24, {'from': user})

    pos = position_helper.addLiquidityAndCreatePosition(  # noqa
        spa,
        usds,
        1e22,
        1e21,
        0,
        0,
        chain.time() + 1000,
        user,
        nft_pool_addr,
        0,
        {'from': user}
    )

    token_id = pool.tokenOfOwnerByIndex(user, 0)

    tx = pool.safeTransferFrom(  # noqa
        user,
        farm,
        token_id,
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        {'from': user}
    )
