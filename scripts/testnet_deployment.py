from brownie import (
    Contract,
    CustomERC20,
    TUP,
    FarmFactory,
    PA,
    Demeter_UniV3FarmDeployer,
    Demeter_UniV3Farm,
    network,
    chain
)
    
import json
from .utils import get_account
import eth_utils
from brownie.network import gas_price
from brownie.network.gas.strategies import LinearScalingStrategy

DEPLOYMENT_ARTIFACTS = f"deployed/{network.show_active()}/deployment_data.json"
# Polygon Mumbai specific addresses
UNISWAP_UTILS = "0xBcA67BAd52F90F4A461C27bd5FBd77b9A2329b89"
NONFUNGIBLE_POSITION_MANAGER_UTILS = "0xb97FB0dD108C0882C3A556de37376E17c0587401"
UNISWAP_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
GAS_LIMIT = 1e7
FARM_OWNER:str or bool = False
FEE_AMOUNT:int or bool = 1e18
FEE_RECEIVER: str or bool = False
REWARD_DATA = []
DEPOSIT_AMOUNT = 1e18
# Uniswap Pool Info
UNISWAP_POOL_FEE = 3000
UNISWAP_TICK_LOWER = -887220
UNISWAP_TICK_UPPER = 887220
VERIFY = True

class Token:
    def __init__(self, name, symbol, decimals):
        self.name = name
        self.symbol = symbol
        self.decimals = decimals

tokens = {
    "usds": Token("Sperax USD", "USDs", 18),
    "spa": Token("Sperax", "SPA", 18),
    "usdc": Token("USDC", "USDC", 6),
    "dai": Token("Dai", "DAI", 18),
    # "usdt": Token("Tether", "USDT", 6),
    # "arb": Token("ARB", "ARB", 18),
    # "frax": Token("Frax", "FRAX", 18),
    # "lusd": Token("lUsd", "LUSD", 18),
}

def deploy(deployments, contract, args, key):
    if key in deployments.keys():
        print(f"\n Using pre-deployed {key}\n")
        return contract.at(deployments[key]), False
    else:
        return contract.deploy(*args, publish_source=VERIFY), True
    
def createUniswapV3Farm(owner, farmFactory, uniswapV3FarmDeployer: Contract, data):
    print("\n -- Deploying Demeter_UniV3Farm USDs and SPA contract -- \n")
    input("Is UniswapV3 pool created for USDs and SPA?. No not please create it first and then press enter to continue.")
    farmData = [
        owner,
        chain.time() + 100,
         1,  # lockup functionality
         [
             data["USDs"],
             data["SPA"],
             UNISWAP_POOL_FEE,
             UNISWAP_TICK_LOWER,
             UNISWAP_TICK_UPPER,
         ],
        REWARD_DATA
    ]
    uniswapV3FarmDeployer.createFarm(farmData, {"from": owner, "gas_limit": GAS_LIMIT})
    demeterUniV3Farm = farmFactory.farms(0)
    demeterUniV3Farm = Contract.from_abi("Demeter_UniV3Farm", demeterUniV3Farm, Demeter_UniV3Farm.abi)
    return demeterUniV3Farm

# Under dev
# def deposit(owner, demeterUniV3Farm: Contract, data):
#     token0Addr = data["USDs"]
#     token1Addr = data["SPA"]
#     nfpm = Contract.from_abi("NonfungiblePositionManager", demeterUniV3Farm.NFPM(), INFPM.abi)
#     CustomERC20.at(token0Addr).mint(owner, DEPOSIT_AMOUNT)
#     CustomERC20.at(token0Addr).approve(nfpm.address, DEPOSIT_AMOUNT)

#     CustomERC20.at(token1Addr).mint(owner, DEPOSIT_AMOUNT)
#     CustomERC20.at(token1Addr).approve(nfpm.address, DEPOSIT_AMOUNT)

#     tx = nfpm.mint(token0Addr, token1Addr, UNISWAP_POOL_FEE, UNISWAP_TICK_LOWER,UNISWAP_TICK_UPPER, DEPOSIT_AMOUNT, 0,0,owner, chain.time() + 84600, {"from": owner, "gas_limit": GAS_LIMIT})
#     print(tx.return_value)
#     nfpm.safeTransferFrom(owner, demeterUniV3Farm, tx.return_value[0], {"from": owner, "gas_limit": GAS_LIMIT})


def main():
    owner = get_account("Select deployer ")
    gas_strategy = LinearScalingStrategy("3 gwei", "5 gwei", 1.1)
    gas_price(gas_strategy)

    deployments = {}
    data = {}
    try:
        with open(DEPLOYMENT_ARTIFACTS) as file:
            deployments = json.load(file)
    except FileNotFoundError:
        deployments = {}
    
    # Deploy all the ERC20 contracts
    print("\n -- Deploying ERC20 contracts -- \n")
    for tkn in tokens.keys():
        token = tokens[tkn]
        print(f"\n -Deploying {token.symbol}")
        tkn_contract, _ = deploy(
            deployments,
            CustomERC20,
            [token.name, token.symbol, token.decimals, {"from": owner, "gas_limit": GAS_LIMIT}],
            token.symbol,
        )
        vars()[token.symbol] = tkn_contract
        data[token.symbol] = tkn_contract.address


    # Deploy FarmFactory
    print("\n -- Deploying FarmFactory contract -- \n")
    farmFactoryImpl,_ = deploy(deployments, FarmFactory, [{"from": owner, "gas_limit": GAS_LIMIT}], "farmFactoryImpl")
    data["farmFactoryImpl"] = farmFactoryImpl.address
    proxyAdmin,_ = deploy(deployments, PA, [{"from": owner, "gas_limit": GAS_LIMIT}], "proxyAdmin")
    data["proxyAdmin"] = proxyAdmin.address
    farmFactory, isNewFarmFactory= deploy(
        deployments,
        TUP,
        [farmFactoryImpl, proxyAdmin, eth_utils.to_bytes(hexstr="0x"), {"from": owner, "gas_limit": GAS_LIMIT}],
        "farmFactory",
    )
    data["farmFactory"] = farmFactory.address
    farmFactory = Contract.from_abi("FarmFactory", farmFactory, FarmFactory.abi)
    if isNewFarmFactory:
        # Initialize FarmFactory
        # TODO who is feeReceiver and feeAmount?
        farmFactory.initialize(
            owner,
            data["USDs"],
            0, # feeAmount
            {"from": owner, "gas_limit": GAS_LIMIT}
        )
    
    # Deploy FarmDeployer
    ## Deploy UniswapFarmDeployer
    print("\n -- Deploying Demeter_UniV3FarmDeployer contract -- \n")
    uniswapV3FarmDeployer, isNewUniswapV3FarmDeployer = deploy(
        deployments,
        Demeter_UniV3FarmDeployer,
        [
            farmFactory.address,
            UNISWAP_UTILS,
            NONFUNGIBLE_POSITION_MANAGER_UTILS,
            {"from": owner, "gas_limit": GAS_LIMIT}
        ],
        "uniswapV3FarmDeployer"
    )
    uniswapV3FarmDeployer = Contract.from_abi(
        "uniswapV3FarmDeployer",
        uniswapV3FarmDeployer, 
        Demeter_UniV3FarmDeployer.abi
    )
    data["uniswapV3FarmDeployer"] = uniswapV3FarmDeployer.address


    if isNewUniswapV3FarmDeployer:
        # Verify Demeter_UniV3Farm implementation
        try:
            # TODO failing!
            farmImplementation = Demeter_UniV3Farm.at(uniswapV3FarmDeployer.farmImplementation())
            Demeter_UniV3Farm.publish_source(farmImplementation)
        except Exception as e:
            print(f"An error occurred: {str(e)}")
        # Register deployer on FarmFactory
        farmFactory.registerFarmDeployer(uniswapV3FarmDeployer.address, {"from": owner, "gas_limit": GAS_LIMIT})

    demeterUniV3Farm: Contract
    if "demeterUniV3Farm" not in deployments.keys():
        demeterUniV3Farm = createUniswapV3Farm(owner,farmFactory,uniswapV3FarmDeployer,data)
        data["demeterUniV3Farm"] = demeterUniV3Farm.address
    else: 
        demeterUniV3Farm = Contract.from_abi("Demeter_UniV3Farm", deployments["demeterUniV3Farm"], Demeter_UniV3Farm.abi)

    if FARM_OWNER:
        if farmFactory.owner() is not FARM_OWNER:
            farmFactory.transferOwnership(owner, {"from": farmFactory.owner(), "gas_limit": GAS_LIMIT})
        farmFactory.transferOwnership(FARM_OWNER, {"from": owner, "gas_limit": GAS_LIMIT})
    if FEE_AMOUNT:
        # Does not take account if FEE_RECEIVER is different
        if farmFactory.feeAmount() != FEE_AMOUNT:
            farmFactory.updateFeeParams(FEE_RECEIVER or owner, data["USDs"], FEE_AMOUNT, {"from": farmFactory.owner(), "gas_limit": GAS_LIMIT})


    # Save deployment data
    data = {
        **data,
    }

    deployments = {**deployments, **data}
    with open(DEPLOYMENT_ARTIFACTS, 'w') as outfile:
        json.dump(deployments, outfile)

    
