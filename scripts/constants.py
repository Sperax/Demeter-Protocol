from brownie import (
    FarmRegistry,
    UniV3FarmDeployer,
    UniV3Farm,
    CamelotV2Farm,
    CamelotV2FarmDeployer,
    UniV2FarmDeployer,
    BalancerV2FarmDeployer,
    FarmRegistry,
    RewarderFactory,
    CamelotV3FarmDeployer,
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


deployment_config = {
    'FarmFactory_v1': Deployment_data(
        contract=FarmRegistry,
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
    'UniV3FarmDeployer_v3': Deployment_data(
        contract=UniV3FarmDeployer,
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
    'CamelotFarmDeployer_v1': Deployment_data(
        contract=CamelotV2FarmDeployer,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'protocol_factory':
                    '0x6EcCab422D763aC031210895C81787E87B43A652'
            },
            post_deployment_steps=[
                Step(
                    func='transferOwnership',
                    transact=True,
                    args={
                        #0x12DBb60bAd909e6d9139aBd61D0c9AA11eB49D51
                        'new_owner':
                            '0x6d5240f086637fb408c7F727010A10cf57D51B62'
                    }
                ),
            ]
        )
    ),
    'SushiSwapFarmDeployer_v1': Deployment_data(
        contract=UniV2FarmDeployer,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'SushiSwap_factory':
                    '0xc35DADB65012eC5796536bD9864eD8773aBc74C4',
                'deployer_name': 'Demeter_SushiSwap_Farm'
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
    'TraderJoeFarmDeployer_v1': Deployment_data(
        contract=UniV2FarmDeployer,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'SushiSwap_factory':
                    '0xaE4EC9901c3076D0DdBe76A520F9E90a6227aCB7',
                'deployer_name': 'Demeter_TraderJoe_Farm'
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
    'Demeter_UniV3Farm_implementation': Deployment_data(
        contract=UniV3Farm,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={},
            post_deployment_steps=[
                Step(
                    func='renounceOwnership',
                    transact=True,
                    args={}
                ),
            ]
        )
    ),
    'Demeter_BalancerFarmDeployer': Deployment_data(
        contract=BalancerV2FarmDeployer,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_factory': '0xC4fb09E0CD212367642974F6bA81D8e23780A659',
                'Balancer_Vault':
                    '0xBA12222222228d8Ba445958a75a0704d566BF2C8',
                'deployer_name': 'Demeter_Balancer_Farm'
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
    
    # Demeter V2 deployments 
    'FarmRegistry': Deployment_data(
        contract=FarmRegistry,
        config=Deployment_config(
            upgradeable=True,
            deployment_params={
                'fee_receiver': '0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3', # Buyback
                'fee_token': '0xD74f5255D557944cf7Dd0E45FF521520002D5748', # USDs
                'fee_amount': 100e18, # 100 USDs
                'extension_fee_per_day': 1e18 # 1 USDs
            }
            # post_deployment_steps=[
            #     Step(
            #         func='transferOwnership',
            #         transact=True,
            #         args={
            #             'new_owner':
            #                 '0x6d5240f086637fb408c7F727010A10cf57D51B62'
            #         }
            #     ),
            # ]
        )
    ),
    'RewarderFactory': Deployment_data(
        contract=RewarderFactory,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'oracle': '0x14D99412dAB1878dC01Fe7a1664cdE85896e8E50'
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
                Step(
                    func='deployRewarder',
                    transact=True,
                    args={
                        'reward_token':
                            '0x912CE59144191C1204E64559FE8253a0e49E6548'
                    }
                ),
                Step(
                    func='deployRewarder',
                    transact=True,
                    args={
                        'reward_token':
                            '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'
                    }
                ),
            ]
        )
    ),
    'CamelotV3FarmDeployer': Deployment_data(
        contract=CamelotV3FarmDeployer,
        config=Deployment_config(
            upgradeable=False,
            deployment_params={
                'farm_registry': '0x45bC6B44107837E7aBB21E2CaCbe7612Fce222e0', # To be updated post registry's deployment
                'farm_id': 'Demeter_CamelotV3_NonExpirable_Farm_v1',
                'camelotv3_factory': '0x1a3c9B1d2F0529D97f2afC5136Cc23e58f1FD35B',
                'camelotv3_nfpm': '0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15',
                'camelotv3_utils': '0xA9d3B0B4D2cbC9D35463E7317ca95578e1805a45',
                'camelotv3_nfpm_utils': '0xaB39C3d042BA31978087a4b946baBc8C80d868a4'
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
    )
}

upgrade_config = {
    'farm_factory_v2': Upgrade_data(
        contract=FarmRegistry,
        config=Upgrade_config(
            proxy_address='0xC4fb09E0CD212367642974F6bA81D8e23780A659',
            proxy_admin='0x474b9be3998Ab278b2846dB7C667497f16F83e0C'
        )
    )
}

farm_config = {
    'l2dao_usds_v1': Create_Farm_data(
        contract=UniV3Farm,
        deployer_contract=UniV3FarmDeployer,
        deployer_address='0xe9426fCF504D448CC2e39783f1D1111DC0d8E4E0',
        config=Farm_config(
            deployment_params={
                'farm_admin': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                'farm_start_time': chain.time() + 100,
                'cooldown_period': 0,
                'pool_data': {
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
    ),
    'usds_usdc_camelot_Farm': Create_Farm_data(
        contract=CamelotV2Farm,
        deployer_contract=CamelotV2FarmDeployer,
        deployer_address='0x1a85c90cfEE9eD499C598a11ea56A8E5a16c307f',
        config=Farm_config(
            deployment_params={
                'farm_admin': '0x5b12d9846F8612E439730d18E1C12634753B1bF1',
                'farm_start_time': chain.time() + 100,
                'cooldown_period': 0,
                'pool_data': {
                    'token_A': '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                    'token_B': '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                },
                'reward_token_data': []
            }
        )
    ),
}
