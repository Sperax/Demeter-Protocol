from brownie import (
    accounts,
    Contract,
    chain,
    UniswapFarmV1,
    UniswapFarmV1Deployer,
    TransparentUpgradeableProxy,
    FarmFactory
)
import eth_utils

GAS_LIMIT = 80000000
MULTI_SIG = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'


def main():
    deployer = accounts[0]

    factory_impl = FarmFactory.deploy(
        {'from': deployer}
    )
    proxy = TransparentUpgradeableProxy.deploy(
        factory_impl.address,
        '0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25',
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    factory = Contract.from_abi(
        'FarmFactory',
        proxy.address,
        FarmFactory.abi
    )

    factory.initialize(
        '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
        500e18,
        {'from': deployer}
    )

    farm_deployer = UniswapFarmV1Deployer.deploy(factory, {'from': deployer})
    factory.registerFarmDeployer(
        'UniswapFarmV1Deployer',
        farm_deployer,
        {'from': deployer}
    )

    data = farm_deployer.encodeDeploymentParam(
        (
            deployer,
            chain.time()+100,
            0,
            (
                '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                3000,
                -48960,
                -6900
            ),
            [
                (
                    '0x2CaB3abfC1670D1a452dF502e216a66883cDf079',
                    '0x5b12d9846F8612E439730d18E1C12634753B1bF1'
                )
            ]
        ),
        {'from': deployer}
    )

    create_tx = factory.createFarm(
        'UniswapFarmV1Deployer',
        data,
        {'from': deployer}
    )
    farm_implementation = UniswapFarmV1.at(farm_deployer.implementation())  # noqa
    farm = UniswapFarmV1.at(create_tx.new_contracts[0])  # noqa
