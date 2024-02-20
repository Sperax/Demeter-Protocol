# from brownie import (
#     Demeter_BalancerFarm_Deployer,
#     chain,
#     interface
# )
from ape import project, chain, accounts

factory = "0xC4fb09E0CD212367642974F6bA81D8e23780A659"
balancerVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"
OWNER = accounts["0x6d5240f086637fb408c7F727010A10cf57D51B62"]
USDs_Address = "0xD74f5255D557944cf7Dd0E45FF521520002D5748"
usdsFunder = accounts["0x5c9d09716404556646B0B4567Cb4621C18581f94"]
USDs = project.dependencies["OpenZeppelin"]["4.9.5"].IERC20.at(USDs_Address)


def createFarm(farmDeployer, creatorAddress):
    creator = accounts[creatorAddress]
    creator.balance += int(10e18)
    usdsFunder.balance += int(10e18)
    params = {
        "farm-admin": OWNER,
        "farm-start-time": chain.pending_timestamp,
        "cooldown-period": 0,
        "pool-id": "0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496",  # noqa
        "reward-token-data": [
            (
                USDs.address,
                creator.address,
            ),
        ],
    }
    USDs.transfer(creator, int(100e18), sender=usdsFunder)
    USDs.approve(farmDeployer, int(100e18), sender=creator)
    project.IFarmFactory.at(factory).registerFarmDeployer(farmDeployer, sender=OWNER)
    tx = farmDeployer.createFarm(
        (
            params["farm-admin"].address,
            params["farm-start-time"],
            params["cooldown-period"],
            params["pool-id"],
            params["reward-token-data"],
        ),
        sender=creator,
    )
    return tx


def main():
    # creator = input("Enter user's address: ")
    creator = "0x12DBb60bAd909e6d9139aBd61D0c9AA11eB49D51"
    OWNER.balance += int(10e18)
    farmDeployer = project.Demeter_BalancerFarm_Deployer.deploy(
        factory, "Demeter Balancer Deployer", balancerVault, sender=OWNER
    )
    print("Demeter balancer farm deployer deployed", farmDeployer)
    print("Creating farm ...")
    tx = createFarm(farmDeployer, creator)
    print(tx.events)
