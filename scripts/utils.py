from brownie import (
    network,
    accounts
)
import click
import sys
import time
import json
import os


def signal_handler(signal, frame):
    sys.exit(0)


def _getYorN(msg):
    while True:
        answer = input(msg + ' [y/n] ')
        lowercase_answer = answer.lower()
        if lowercase_answer == 'y' or lowercase_answer == 'n':
            return lowercase_answer
        else:
            print('Please enter y or n.')


def get_account(msg: str):
    owner = accounts.load(
        click.prompt(
            msg,
            type=click.Choice(accounts.load())
        )
    )
    print(f'{msg}: {owner.address}\n')
    return owner


def get_config(msg: str, constants):
    config_name = (
        click.prompt(
            msg,
            type=click.Choice(list(constants.keys()))
        )
    )
    return (
        config_name,
        constants[config_name]
    )


def confirm(msg):
    """
    Prompts the user to confirm an action.
    If they hit yes, nothing happens, meaning the script continues.
    If they hit no, the script exits.
    """
    answer = _getYorN(msg)
    if answer == 'y':
        return
    elif answer == 'n':
        print('Exiting...')
        exit()


def choice(msg):
    """
    Prompts the user to choose y or n. If y, return true. If n, return false
    """
    answer = _getYorN(msg)
    if answer.lower() == 'y':
        return True
    else:
        return False


def onlyDevelopment(func):
    """
    Checks if the network is in the list of testnet or mainnet forks.
    If so, it calls the function
    If not does nothing
    """
    dev_networks = [
        'arbitrum-rinkeby',
        'arbitrum-main-fork',
        'development',
        'geth-dev',
        'rinkeby'
    ]
    if network.show_active() in dev_networks:
        func()  # can also just return t/f


def save_deployment_artifacts(data, name):
    # Function to store deployment artifacts
    path = os.path.join('deployed', network.show_active())
    os.makedirs(path, exist_ok=True)
    file = os.path.join(
        path,
        name + '_' + time.strftime('%m-%d-%Y_%H:%M:%S') + '.json'
    )
    with open(file, 'w') as json_file:
        json.dump(data, json_file, default=lambda o: o.__dict__, indent=4)
    print(f'Artifacts stored at: {file}')
