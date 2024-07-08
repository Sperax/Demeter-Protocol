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

def main():
    owner = get_user('Select deployer ')

    # Deploy all the ERC20 contracts
    arb = ERC20.at('0x912CE59144191C1204E64559FE8253a0e49E6548')
    usdc = ERC20.at('0xaf88d065e77c8cC2239327C5EDb3A432268e5831')
    usds = ERC20.at('0xD74f5255D557944cf7Dd0E45FF521520002D5748')
    spa = ERC20.at('0x5575552988a3a80504bbaeb1311674fcfd40ad4b')

    # Base contracts
    farmRegistry = Contract.from_abi('FarmRegistry', '0x45bC6B44107837E7aBB21E2CaCbe7612Fce222e0', FarmRegistry.abi)
    rewarderFactory = Contract.from_abi('RewarderFactory', '0x382B536873746b36faCBC0d45cDE17D122affB79', RewarderFactory.abi)
    arbRewarder = Contract.from_abi('Rewarder', '0x9418678F11298e847F420BC8276BA1e459b51f01', Rewarder.abi)
    spaRewarder = Contract.from_abi('Rewarder', '0x3529D51de1c473cD78D439784825f40738f001FD', Rewarder.abi)
    
    camelotV3Deployer = Contract.from_abi('CamelotV3Deployer', '0x212208daF12D7612e65fb39eE9a07172b08226B8', CamelotV3FarmDeployer.abi)
    