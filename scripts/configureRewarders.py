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

FILE_NAME = '6_august'
ONE_WEEK = 604800
STANDARD_DECIMALS = 18
ONE_YEAR = 86500 * 365
ORACLE = interface.IOracle('0x14D99412dAB1878dC01Fe7a1664cdE85896e8E50')
usdBudgets = [int(7538 * 1e18), int(9423 * 1e18), int(1885 * 1e18)] # xSPA, Arb, Spa
top_tx_obj = {
    "version": "1.0",
    "chainId": "42161",
    "createdAt": 1709788285087, # @todo ts in ms
    "meta": {
        "name": "July 24 Demeter Rewarder Configuration",
        "description": "Updating reward config in 3 rewarders for 7 farms",
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
          "components": [
            {
              "internalType": "uint256",
              "name": "apr",
              "type": "uint256"
            },
            {
              "internalType": "uint128",
              "name": "maxRewardRate",
              "type": "uint128"
            },
            {
              "internalType": "address[]",
              "name": "baseTokens",
              "type": "address[]"
            },
            {
              "internalType": "uint256",
              "name": "nonLockupRewardPer",
              "type": "uint256"
            }
          ],
          "internalType": "struct IRewarder.FarmRewardConfigInput",
          "name": "_rewardConfig",
          "type": "tuple"
        }
      ],
      "name": "updateRewardConfig",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
}

def getActualApr(farm, rewardToken, considerableValueForRewards):
  price = ORACLE.getPrice(rewardToken)
  rewardRates = farm.getRewardRates(rewardToken)
  rewardRate = rewardRates[0] + rewardRates[1]
  rewardRate = normalizeAmount(rewardToken, rewardRate)
  rewardsPerYear = rewardRate * ONE_YEAR
  value = ((rewardsPerYear * price[0]) / price[1])
  return (value * 100) / considerableValueForRewards

def save_dict_to_json(data_dict, json_file):
    try:
        # Write dictionary to JSON file
        with open(json_file, 'w') as file:
            json.dump(data_dict, file, indent=4)
        print("Dictionary saved to", json_file)
    except Exception as e:
        print("Error saving dictionary to JSON file:", e)
        
oz_project = project.load(BrownieConfig["dependencies"][4])
ERC20 = oz_project.ERC20
USDs = '0xD74f5255D557944cf7Dd0E45FF521520002D5748'
usds = ERC20.at(USDs)

def normalizeAmount(token, amount):
  token = ERC20.at(token)
  decimals = token.decimals()
  if (decimals < STANDARD_DECIMALS):
    amount = int(amount * 10 ** (STANDARD_DECIMALS - decimals))
  if (decimals > STANDARD_DECIMALS):
    amount = int(amount / 10 ** (decimals - STANDARD_DECIMALS))
  return amount

def getValue(token, amount):
  tokenPrice = ORACLE.getPrice(token)
  value = int((amount * tokenPrice[0]) / tokenPrice[1])
  return normalizeAmount(token, value)

def getFarmData(rewarders, farms):
    print('Getting farm data')
    # tokenBudgets = [int(814566 * 1e18), int(12090 * 1e18), int(203642 * 1e18)] # xSPA, Arb, Spa
    tokenBudgets = [] # xSPA, Arb, Spa
    for i in range(len(rewarders)):
      rewarderContract = Contract.from_abi('Rewarder', rewarders[i], Rewarder.abi)
      price = ORACLE.getPrice(rewarderContract.REWARD_TOKEN())
      tokenBudgets.append(int(((usdBudgets[i] * price[1]) / price[0]))/ONE_WEEK)
      
    tvl = 0
    farmDatas = []
    for farm in farms:
        farm = Contract.from_abi('CamelotV3Farm', farm, CamelotV3Farm.abi)
        if farm.isFarmActive():
            tokenAmounts = farm.getTokenAmounts()
            thisTVL = (getValue(tokenAmounts[0][0], tokenAmounts[1][0]) + getValue(tokenAmounts[0][1], tokenAmounts[1][1]))
            farmDatas.append({
                'farm': farm.address,
                'tvl': thisTVL,
                'baseTokens': tokenAmounts[0]
            })
            tvl += thisTVL
    for i in range(len(farmDatas)):
        farmDatas[i]['percentage'] = farmDatas[i]['tvl'] / tvl
        farmDatas[i]['maxRewardRates'] = []
        for j in range(len(rewarders)):
            farmDatas[i]['maxRewardRates'].append({
                'rewarder': rewarders[j],
                'maxRewardRate': int(tokenBudgets[j] * farmDatas[i]['percentage'])
            })
    return farmDatas

def main():
    rewarders = ['0x6bed024CBeCEcA3CEE0bb04a967857CF9554FEcB', '0xB0e50AbaEACE0715D5b84A9769750D3E48c4509E', '0xFB64f50d0BDE4595187632525eb6cfFB5D18B486']
    farmRegistry = Contract.from_abi('FarmRegistry', '0x45bC6B44107837E7aBB21E2CaCbe7612Fce222e0', FarmRegistry.abi)
    farms = farmRegistry.getFarmList()
    farmDatas = getFarmData(rewarders, farms)

    transactions = []
    print('Creating transactions')
    for farmData in farmDatas:
        for j in range(len(rewarders)):
            tx = {}
            rewarderContract = Contract.from_abi('Rewarder', rewarders[j], Rewarder.abi)
            config = rewarderContract.getRewardConfig(farmData['farm'])
            data = {
                'to': rewarders[j],
                'contractInputsValues': {
                    '_farm': farmData['farm'],
                    '_rewardConfig': f'[\"{int(config[0]/2)}\",\"{farmData['maxRewardRates'][j]['maxRewardRate']}\",[\"{farmData['baseTokens'][0]}\",\"{farmData['baseTokens'][1]}\"],\"{config[4]}\"]'
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
    simulateTransactions(farmDatas, rewarders)
    
def simulateTransactions(farmDatas, rewarders):
  print('Simulating transactions')
  for farmData in farmDatas:
    for j in range(len(rewarders)):
      rewarderContract = Contract.from_abi('Rewarder', rewarders[j], Rewarder.abi)
      config = rewarderContract.getRewardConfig(farmData['farm'])
      rewarderContract.updateRewardConfig(farmData['farm'], [int(config[0]/2), farmData['maxRewardRates'][j]['maxRewardRate'], farmData['baseTokens'], config[4]], {'from': rewarderContract.owner()})

  # Verification
  allocatedBudgets = [0,0,0]
  config = [[0 for x in range(len(rewarders))] for y in range(len(farmDatas))]
  for i in range(len(farmDatas)):
    for j in range(len(rewarders)):
      rewarderContract = Contract.from_abi('Rewarder', rewarders[j], Rewarder.abi)
      config[i][j] = rewarderContract.getRewardConfig(farmDatas[i]['farm'])
      allocatedBudgets[j] += config[i][j][2]
  
  for i in range(len(farmDatas)):
    print()
    print('Farm', farmDatas[i]['farm'])
    print('TVL', farmDatas[i]['tvl'])
    print('TVL percentage', farmDatas[i]['percentage'] * 100)
    print('APR in rewarder', config[i][0][0]/1e8)
    print('APR in rewarder', config[i][1][0]/1e8)
    print('APR in rewarder', config[i][2][0]/1e8)
    print('Max reward rate percentage', (config[i][0][2] / allocatedBudgets[0]) * 100)
    print('Max reward rate percentage', (config[i][1][2] / allocatedBudgets[1]) * 100)
    print('Max reward rate percentage', (config[i][2][2] / allocatedBudgets[2]) * 100)
    print('Max reward rate', config[i][0][2]/1e18)
    print('Max reward rate', config[i][1][2]/1e18)
    print('Max reward rate', config[i][2][2]/1e18)
  
  print('Calibrating rewards')
  for farmData in farmDatas:
    for j in range(len(rewarders)):
      rewarderContract = Contract.from_abi('Rewarder', rewarders[j], Rewarder.abi)
      rewarderContract.calibrateReward(farmData['farm'], {'from': '0x12DBb60bAd909e6d9139aBd61D0c9AA11eB49D51'})
  
  print('Actual APR in the farm')
  for farmData in farmDatas:
    farm = Contract.from_abi('CamelotV3Farm', farmData['farm'], CamelotV3Farm.abi)
    for j in range(len(rewarders)):
      rewarderContract = Contract.from_abi('Rewarder', rewarders[j], Rewarder.abi)
      rewardToken = rewarderContract.REWARD_TOKEN()
      print()
      print('Farm', farmData['farm'])
      print('Reward token', rewardToken)
      print('Actual APR', int(getActualApr(farm, rewarderContract.REWARD_TOKEN(), farmData['tvl'])))
