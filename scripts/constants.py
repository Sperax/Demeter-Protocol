from brownie import (
    FarmFactory,
    GaugeController,
    Demeter_UniV3FarmDeployer_v2,
    Demeter_UniV3Farm_v2,
    chain,
)


class Step():
    def __init__(
        self,
        func,
        args,
        transact,
        contract=None,
        contract_addr=''
    ):
        self.func = func
        self.args = args
        self.transact = transact
        self.contract = contract
        self.contract_addr = contract_addr


class Deployment_config():
    def __init__(
        self,
        deployment_params,
        post_deployment_steps=[],
        upgradeable=False,
        proxy_admin=None
    ):
        self.deployment_params = deployment_params
        self.post_deployment_steps = post_deployment_steps
        self.upgradeable = upgradeable
        self.proxy_admin = proxy_admin


class Upgrade_config():
    def __init__(
        self,
        proxy_address,
        proxy_admin,
        gnosis_upgrade=True,
        post_upgrade_steps=[]
    ):
        self.proxy_address = proxy_address
        self.gnosis_upgrade = gnosis_upgrade
        self.proxy_admin = proxy_admin
        self.post_upgrade_steps = post_upgrade_steps


class Farm_config():
    def __init__(
        self,
        deployment_params,
        post_deployment_steps=[]
    ):
        self.deployment_params = deployment_params
        self.post_deployment_steps = post_deployment_steps


class Upgrade_data():
    def __init__(self, contract, config: Upgrade_config):
        self.contract = contract
        self.config = config


class Deployment_data():
    def __init__(self, contract, config: Deployment_config):
        self.contract = contract
        self.config = config


class Create_Farm_data():
    def __init__(
        self,
        contract,
        deployer_contract,
        deployer_address,
        config: Farm_config
    ):
        self.contract = contract
        self.deployer_contract = deployer_contract
        self.deployer_address = deployer_address
        self.config = config


vespa_constants = {
    'arbitrum-main-fork': {
        'veSPA': '0x2e2071180682Ce6C247B1eF93d382D509F5F6A17',
        'spa': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
        'emergency_return': '0x3702E3e2DB2b5d037c1dbB23Ab7A51d0Cc90BD0e',
    },
    'arbitrum-one': {
        'veSPA': '0x2e2071180682Ce6C247B1eF93d382D509F5F6A17',
        'spa': '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
        'emergency_return': '0x3702E3e2DB2b5d037c1dbB23Ab7A51d0Cc90BD0e',
        # Arbitrum staking-multisig
    },
    'mainnet': {
        'veSPA': '0xbF82a3212e13b2d407D10f5107b5C8404dE7F403',
        'spa': '0xB4A3B0Faf0Ab53df58001804DdA5Bfc6a3D59008',
        'emergency_return': '0xCD1B1ce6ce877a9315E73E2E4Ba3137228068A59',
        # Ethereum staking-multisig
    }
}


deployment_config = {
    'FarmFactory_v1': Deployment_data(
        contract=FarmFactory,
        config=Deployment_config(
            upgradeable=True,
            deployment_params={
                'fee_receiver': '0x4F987B24bD2194a574bB3F57b4e66B7f7eD36196',
                'fee_token': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                'fee_amount': 500e18
            },
            post_deployment_steps=[
                Step(
                    func='transferOwnership',
                    transact=True,
                    args={
                        'new_owner':
                            '0x6d5240f086637fb408c7F727010A10cf57D51B62'
                    }
                ),
                # Transfer Ownership for proxyAdmin
                # Step(
                #     contract=ProxyAdmin
                #     transact=True,
                #     func='transferOwnership',
                #     args={
                #         'new_owner':
                #             '0xEeE35407BC8eAF4D82A7CD4876f87dD0De2f07B8'
                #     }
                # )
            ]
        )
    ),
    'UniV3FarmDeployer_v2': Deployment_data(
        contract=Demeter_UniV3FarmDeployer_v2,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659'
            },
            post_deployment_steps=[
                Step(
                    func='transferOwnership',
                    transact=True,
                    args={
                        'new_owner':
                            '0x6d5240f086637fb408c7F727010A10cf57D51B62'
                    }
                ),
            ]
        )
    ),
    'gauge_controller_v1': Deployment_data(
        contract=GaugeController,
        config=Deployment_config(
            deployment_params={
                'veSPA': vespa_constants['arbitrum-one']['veSPA']
            },
            upgradeable=False,
        )
    )
}

upgrade_config = {}

farm_config = {
    'l2dao_usds_v1': Create_Farm_data(
        contract=Demeter_UniV3Farm_v2,
        deployer_contract=Demeter_UniV3FarmDeployer_v2,
        deployer_address='0xe9426fCF504D448CC2e39783f1D1111DC0d8E4E0',
        config=Farm_config(
            deployment_params={
                'farm_admin': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                'farm_start_time': chain.time() + 100,
                'cooldown_period': 0,
                'uniswap_pool_data': {
                    'token_A': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                    'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'fee_tier': 3000,
                    'lower_tick': -48960,
                    'upper_tick': -6900,
                },
                'reward_token_data': [
                    {
                        'reward_tkn':
                            '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                        'tkn_manager':
                            '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                    },
                ]
            }
        )
    )
}
