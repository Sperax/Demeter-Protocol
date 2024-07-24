from brownie import Contract, network, config as BrownieConfig, accounts, project

if network.show_active() in ["arbitrum-sepolia"]:

    from .testnet_constants import (
        Create_Farm_data,
        Deployment_data,
        Upgrade_data,
        deployment_config,
        upgrade_config,
        farm_config,
        Step,
    )
else:
    from .constants import (
        Create_Farm_data,
        Deployment_data,
        Upgrade_data,
        deployment_config,
        upgrade_config,
        farm_config,
        Step,
    )
        
from .utils import get_config, print_dict, _getYorN, confirm, save_deployment_artifacts
import eth_utils
import click
import json

GAS_LIMIT = 40000000

oz_project = project.load(BrownieConfig["dependencies"][0])
ProxyAdmin = oz_project.ProxyAdmin
TransparentUpgradeableProxy = oz_project.TransparentUpgradeableProxy


def resolve_args(args, contract_obj, caller):
    """Resolves derived arguments

    Args:
        args ([]): array str | int | Step
        contract_obj (contract): Current context contract
        caller (address): address of caller

    Returns:
        []str|int|bool: resolved argument array
    """
    res = []
    for arg in args.values():
        if type(arg) is Step:
            arg, val, _ = run_step(arg, contract_obj, caller)
            res.append(val)
        else:
            res.append(arg)
    return args, res


def call_func(contract_obj, func_name, args, transact, caller=None):
    """Interact with a contract

    Args:
        contract_obj (contract): Contract object for interaction
        func_name (str): name of the function
        args ({}): arguments for the function call
        transact (bool): Do a transaction or call
        caller (address): Address of user performing transaction

    Returns:
        val: Returns value for view functions
    """
    func_sig = contract_obj.signatures[func_name]
    func = contract_obj.get_method_object(func_sig)
    args, res = resolve_args(args, contract_obj, caller)
    val = None
    if transact:
        tx = func.transact(*res, {"from": caller, "gas_limit": GAS_LIMIT})
    else:
        tx = None
        val = func.call(
            *res,
        )
    return args, val, tx


def run_step(step, contract_obj, deployer):
    """Run the post deployment steps

    Args:
        steps (Step): Information of a step
        contract_obj (contract): contract_obj
        deployer (address): Address of user performing transaction

    Returns:
        Steps: Returns steps with updated contract information.
    """
    if type(step) is Step:
        if step.transact:
            print(f"\nRunning step: {step.func}()")
        else:
            print(f"\nFetching: {step.func}()")
        contract_obj = contract_obj
        if step.contract is not None:
            contract_obj = Contract.from_abi(
                "", step.contract_address, step.contract.abi
            )
        else:
            step.contract = contract_obj._name
            step.contract_addr = contract_obj.address
        step.args, val, tx = call_func(
            contract_obj, step.func, step.args, step.transact, deployer
        )
    else:
        print("Invalid argument type skipping")
    return step, val, tx


def get_user(msg):
    """Get the address of the users

    Returns:
        address: Returns address of the deployer
    """
    # simulate transacting with vault core from deployer address on fork
    if network.show_active() in ["arbitrum-main-fork", "arbitrum-main-fork-server"]:
        deployer = accounts.at(input(msg), force=True)

    else:
        # contract deployer account
        deployer = accounts.load(click.prompt(msg, type=click.Choice(accounts.load())))
    print(f"{msg}{deployer.address}\n")
    return deployer


def get_tx_info(name, tx):
    data = {}
    data["step"] = name
    data["tx_hash"] = tx.txid
    data["contract"] = tx.contract_name
    data["contract_addr"] = tx.contract_address
    data["tx_func"] = tx.fn_name
    data["blocknumber"] = tx.block_number
    data["gas_used"] = tx.gas_used
    data["gas_limit"] = tx.gas_limit
    return data


def deploy(configuration, deployer):
    """Utility to deploy contracts

    Args:
        configuration (Deployment_data{}): Configuration data for deployment
        deployer (address): address of the deployer

    Returns:
        dict: deployment_data
    """
    config_name, config_data = get_config("Select config for deployment", configuration)
    if type(config_data) is not Deployment_data:
        print("Incorrect configuration data")
        return
    contract = config_data.contract
    conf = config_data.config
    deployment_data = {}
    deployed_contract = None
    tx_list = []
    print(json.dumps(conf, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    if conf.upgradeable:
        print("\nDeploying implementation contract")
        impl = contract.deploy({"from": deployer, "gas_limit": GAS_LIMIT})
        tx_list.append(get_tx_info("Implementation_deployment", impl.tx))

        proxy_admin = conf.proxy_admin

        if proxy_admin is None:
            print("\nDeploying proxy admin contract")
            pa_deployment = ProxyAdmin.deploy(
                deployer, {"from": deployer, "gas_limit": GAS_LIMIT}
            )
            tx_list.append(get_tx_info("Proxy_admin_deployment", pa_deployment.tx))
            proxy_admin = pa_deployment.address

        print("\nDeploying proxy contract")
        proxy = TransparentUpgradeableProxy.deploy(
            impl.address,
            proxy_admin,
            eth_utils.to_bytes(hexstr="0x"),
            {"from": deployer, "gas_limit": GAS_LIMIT},
        )
        tx_list.append(get_tx_info("Proxy_deployment", proxy.tx))

        # Load the deployed contracts
        deployed_contract = Contract.from_abi(config_name, proxy.address, contract.abi)

        print("\nInitializing proxy contract")
        init = deployed_contract.initialize(
            *conf.deployment_params.values(), {"from": deployer, "gas_limit": GAS_LIMIT}
        )

        tx_list.append(get_tx_info("Proxy_initialization", init))

        deployment_data["proxy_addr"] = proxy.address
        deployment_data["impl_addr"] = impl.address
        deployment_data["proxy_admin"] = proxy_admin

    else:
        print(f"\nDeploying {config_name} contract")
        deployed_contract = contract.deploy(
            *conf.deployment_params.values(), {"from": deployer, "gas_limit": GAS_LIMIT}
        )
        tx_list.append(get_tx_info("Deployment_transaction", deployed_contract.tx))

        deployment_data["contract_addr"] = deployed_contract.address

    for step in conf.post_deployment_steps:
        step, _, tx = run_step(step, deployed_contract, deployer)
        if tx is not None:
            tx_list.append(get_tx_info("Post_deployment_step", tx))

    print_dict("Printing deployment data", deployment_data, 20)
    deployment_data["type"] = "Deployment"
    deployment_data["transactions"] = tx_list
    deployment_data["config_name"] = config_name
    deployment_data["config"] = conf
    save_deployment_artifacts(deployment_data, config_name, "Deployment")


def upgrade(configuration, deployer):
    """Utility to upgrade a contract

    Args:
        configuration (_type_): Upgrade configuration list
        deployer (address): Address of the deployer

    Returns:
        _type_: _description_
    """
    config_name, config_data = get_config("Select config for upgrade", configuration)
    if type(config_data) is not Upgrade_data:
        print("Incorrect configuration data")
        return
    contract = config_data.contract
    conf = config_data.config
    upgrade_data = {}
    tx_list = []

    print(json.dumps(conf, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    print("\nDeploying new implementation contract")
    new_impl = contract.deploy({"from": deployer, "gas_limit": GAS_LIMIT})
    tx_list.append(get_tx_info("New_implementation_deployment", new_impl.tx))
    if not conf.gnosis_upgrade:
        admin = deployer
        flag = _getYorN("Is admin same as deployer?")
        if flag == "n":
            admin = get_user("Admin account: ")
        proxy_admin = Contract.from_abi("ProxyAdmin", conf.proxy_admin, ProxyAdmin.abi)
        print("\nPerforming upgrade!")
        upgrade_tx = proxy_admin.upgrade(
            conf.proxy_address,
            new_impl.address,
            {"from": admin, "gas_limit": GAS_LIMIT},
        )
        tx_list.append(get_tx_info("Upgrade_transaction", upgrade_tx))
        deployed_contract = Contract.from_abi(
            config_name, conf.proxy_address, contract.abi
        )
        for step in conf.post_upgrade_steps:
            step, _, tx = run_step(step, deployed_contract, deployer)  # noqa
            if tx is not None:
                tx_list.append(get_tx_info("Post_upgrade_transaction", tx))
    else:
        print("\nPlease switch to Gnosis to perform upgrade!\n")

    upgrade_data["new_impl"] = new_impl.address
    print_dict("Printing Upgrade data", upgrade_data, 20)
    upgrade_data["type"] = "Upgrade"
    upgrade_data["transactions"] = tx_list
    upgrade_data["config_name"] = config_name
    upgrade_data["config"] = conf
    save_deployment_artifacts(upgrade_data, config_name, "Upgrade")
    return upgrade_data


def create_farm(configuration, deployer):
    config_name, config_data = get_config("Select config for deployment", configuration)
    if type(config_data) is not Create_Farm_data:
        print("Incorrect configuration data")
        return
    conf = config_data.config
    print(json.dumps(conf, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    deployer_contract = Contract.from_abi(
        "Deployer_contract",
        config_data.deployer_address,
        config_data.deployer_contract.abi,
    )
    deployment_data = {}
    tx_list = []

    print("Create farm contract.")
    create_tx = deployer_contract.createFarm(
        [
            conf.deployment_params["farm_admin"],
            conf.deployment_params["farm_start_time"],
            conf.deployment_params["cooldown_period"],
            list(conf.deployment_params["pool_data"].values()),
            list(
                map(
                    lambda x: list(x.values()),
                    conf.deployment_params["reward_token_data"],
                )
            ),
        ],
        {"from": deployer},
    )
    tx_list.append(get_tx_info("Create_farm_transaction", create_tx))

    deployed_contract = config_data.contract.at(create_tx.new_contracts[0])

    for step in conf.post_deployment_steps:
        step, _, tx = run_step(step, deployed_contract, deployer)  # noqa
        if tx is not None:
            tx_list.append(get_tx_info("Post_deployment_transaction", tx))

    deployment_data["farm_addr"] = create_tx.new_contracts[0]
    print_dict("Printing Upgrade data", deployment_data, 20)
    deployment_data["type"] = "CreateFarm"
    deployment_data["transactions"] = tx_list
    deployment_data["config_name"] = config_name
    deployment_data["config"] = conf
    save_deployment_artifacts(deployment_data, config_name, "FarmCreation")


def main():
    deployer = get_user("Deployer account: ")
    menu = "\nPlease select one of the following options: \n \
    1. Deploy contract \n \
    2. Upgrade contract \n \
    3. Create farm \n \
    4. Exit \n \
    -> "
    while True:
        choice = input(menu)
        if choice == "1":
            deploy(deployment_config, deployer)  # noqa
        elif choice == "2":
            upgrade(upgrade_config, deployer)  # noqa
        elif choice == "3":
            create_farm(farm_config, deployer)
        elif choice == "4":
            break
        else:
            print("Please select a valid option")
