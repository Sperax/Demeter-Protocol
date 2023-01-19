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


def main():
    gauge_controller = GaugeController.deploy(
        vespa_constants[network.show_active()]['veSPA'],
        {'from': OWNER}
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

    _ = gauge_controller.addType('DemeterFarm', 1, {'from': OWNER})
    for farm in farms:
        farm = Demeter_UniV3Farm_v2.at(farm)
        if not farm.isClosed():
            _ = gauge_controller.addGauge(farm, 0, 0, {'from': OWNER})

    user1 = accounts.at('0xb8a7de41a8d28952a4d253f22c4786c6cd65122f', True)  # noqa
    user2 = accounts.at('0xa7a7acc9b9f3eb7136b3f4e33e95fd68bf28c134', True)  # noqa

    curr_week = (chain.time() // WEEK) * WEEK
    next_week = curr_week + WEEK  # noqa
    vespa = Contract.from_abi(  # noqa
        'vespa',
        vespa_constants[network.show_active()]['veSPA'],
        interface.IveSPA.abi
    )
