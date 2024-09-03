from brownie import (
    config as BrownieConfig,
    FarmRegistry,
    CamelotV3Farm,
    Contract,
    project,
    interface,
    Rewarder
)
import json
import pandas as pd

FILE_NAME = 'PauseRewarder'
top_tx_obj = {
    "version": "1.0",
    "chainId": "42161",
    "createdAt": 1709788285087, # @todo ts in ms
    "meta": {
        "name": "Workaround for pause rewards",
        "description": "Setting the apr to 0 for all the farms",
        "txBuilderVersion": "1.16.3",
        "createdFromSafeAddress": "0x68DEB50d2dB6272fc062d7758B86e272C3d590eE", # @todo change this to demeter owner
        "createdFromOwnerAddress": "",
        "checksum": "0xea6e948691ffe3e9151b091b2bd1c53a5925e81df14014abc66b21d5692a8309" # @todo confirm this
    }
}

base_tx_object =  {
    "value": "0",
    "data": None,
    "contractMethod": {
      "inputs": [
        {
          "internalType": "address",
          "name": "_farm",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "_apr",
          "type": "uint256"
        }
      ],
      "name": "updateAPR",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
}

def save_dict_to_json(data_dict, json_file):
    try:
        # Write dictionary to JSON file
        with open(json_file, 'w') as file:
            json.dump(data_dict, file, indent=4)
        print("Dictionary saved to", json_file)
    except Exception as e:
        print("Error saving dictionary to JSON file:", e)
        
def main():
    rewarder = '0xB0e50AbaEACE0715D5b84A9769750D3E48c4509E'
    rewarderContract = Contract.from_abi('Rewarder', rewarder, Rewarder.abi)
    token = rewarderContract.REWARD_TOKEN()
    farmRegistry = Contract.from_abi('FarmRegistry', '0x45bC6B44107837E7aBB21E2CaCbe7612Fce222e0', FarmRegistry.abi)
    farms = farmRegistry.getFarmList()

    transactions = []
    print('Creating transactions')
    for farm in farms:
        tx = {}
        farmContract = Contract.from_abi('CamelotV3Farm', farm, CamelotV3Farm.abi)
        rewardData = farmContract.getRewardData(token)
        if (farmContract.isFarmActive() and rewardData[0] == rewarder):
            data = {
                'to': rewarder,
                'contractInputsValues': {
                    '_farm': farm,
                    '_apr': 0
                }
            }
            tx.update(base_tx_object)
            tx.update(data)
            transactions.append(tx)
    print(len(transactions))
    tx_batch = {}
    tx_batch.update(top_tx_obj)
    tx_batch.update({'transactions': transactions})
    save_dict_to_json(tx_batch, f'./{FILE_NAME}.json')
    simulateTransactions(rewarderContract, farms, token)
    
def simulateTransactions(rewarderContract, farms, token):
  print('Simulating transactions')
  for farm in farms:
    farmContract = Contract.from_abi('CamelotV3Farm', farm, CamelotV3Farm.abi)
    rewardData = farmContract.getRewardData(token)
    print(rewarderContract == rewarderContract)
    owner = rewarderContract.owner()
    if(farmContract.isFarmActive() and rewardData[0] == rewarderContract):
      print('Before')
      rewardRates = farmContract.getRewardRates(token)
      print(rewardRates)
      rewarderContract.updateAPR(farm, 0, {'from': owner})
      rewarderContract.calibrateReward(farm, {'from': owner})
      print('After')
      rewardRates = farmContract.getRewardRates(token)
      print(rewardRates)            
