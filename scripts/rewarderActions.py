from brownie import (
    config as BrownieConfig,
    FarmRegistry,
    RewarderFactory,
    CamelotV3Farm,
    CamelotV3FarmDeployer,
    Rewarder,
    Contract,
    project,
    accounts
)

from .utils import get_user

oz_project = project.load(BrownieConfig["dependencies"][4])
ERC20 = oz_project.ERC20
MAX_PERCENTAGE = 1e4
MIN_PERCENTAGE = 1e2

def calibrateRewards(owner):
    # Deploy all the ERC20 contracts
    arb = ERC20.at('0x912CE59144191C1204E64559FE8253a0e49E6548')
    usdc = ERC20.at('0xaf88d065e77c8cC2239327C5EDb3A432268e5831')
    usdce = ERC20.at('0xff970a61a04b1ca14834a43f5de4533ebddb5cc8')
    usds = ERC20.at('0xD74f5255D557944cf7Dd0E45FF521520002D5748')
    weth = ERC20.at('0x82aF49447D8a07e3bd95BD0d56f35241523fBab1')
    spa = ERC20.at('0x5575552988a3a80504bbaeb1311674fcfd40ad4b')
    xspa = ERC20.at('0x0966E72256d6055145902F72F9D3B6a194B9cCc3')

    # Base contracts
    farmRegistry = Contract.from_abi('FarmRegistry', '0x45bC6B44107837E7aBB21E2CaCbe7612Fce222e0', FarmRegistry.abi)
    # rewarderFactory = Contract.from_abi('RewarderFactory', '0x382B536873746b36faCBC0d45cDE17D122affB79', RewarderFactory.abi)
    arbRewarder = Contract.from_abi('Rewarder', '0xB0e50AbaEACE0715D5b84A9769750D3E48c4509E', Rewarder.abi)
    xspaRewarder = Contract.from_abi('Rewarder', '0x6bed024CBeCEcA3CEE0bb04a967857CF9554FEcB', Rewarder.abi)
    spaRewarder = Contract.from_abi('Rewarder', '0xFB64f50d0BDE4595187632525eb6cfFB5D18B486', Rewarder.abi)
    rewarders = [arbRewarder, xspaRewarder, spaRewarder]
    
    # camelotV3Deployer = Contract.from_abi('CamelotV3Deployer', '0x212208daF12D7612e65fb39eE9a07172b08226B8', CamelotV3FarmDeployer.abi)

    farms = farmRegistry.getFarmList()
    for i in range(1,8):
        farm = Contract.from_abi("Farm", farms[i], CamelotV3Farm.abi)
        for j in range(3):
            print('*' * 50)
            print('\n *****', i, j, '*****')
            print(farm.getTokenAmounts())
            tx = rewarders[j].calibrateReward(farm, {'from': owner})
            print(tx.info())
            farm.getRewardRates(rewarders[j].REWARD_TOKEN())
    print('Successfully Calibrated', len(rewarders), 'rewarders for', len(farms) - 1, 'farms!')

def updateFarmRewardConfig():
    return # to be implemented
    farmRewardConfigs = [
        ( # ARB
            5e9, # apr
            1261810279667422, # max reward rate
            [
                usds
            ],
            MAX_PERCENTAGE
        ),
        ( # xSPA
            12e9, # apr
            100942460317460317, # max reward rate
            [
                usds
            ],
            MAX_PERCENTAGE
        ),
        ( # SPA
            3e9, # apr
            25235733182161755, # max reward rate
            [
                usds
            ],
            MIN_PERCENTAGE
        )
    ]


def main():
    owner = get_user('Deployer account: ')
    menu = '\nPlease select one of the following options: \n \
    1. Calibrate Rewards \n \
    2. Update farm reward config \n \
    3. Exit \n \
    -> '
    while True:
        choice = input(menu)
        if choice == '1':
            calibrateRewards(owner)
        elif choice == '2':
            updateFarmRewardConfig()
        elif choice == '3':
            break
        else:
            print('Please select a valid option')
