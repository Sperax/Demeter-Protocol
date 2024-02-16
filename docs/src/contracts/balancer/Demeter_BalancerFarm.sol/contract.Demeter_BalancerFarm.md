# Demeter_BalancerFarm

[Git Source](https://github.com/Sperax/Demeter-Protocol/blob/fe40a3b3400612e06e8894e40f27c05bc3ec9a73/contracts/balancer/Demeter_BalancerFarm.sol)

**Inherits:**
[Farm](/contracts/Farm.sol/contract.Farm.md)

**Author:**
Sperax Foundation

An ERC20 farm to support all kinds of Balancer V2 pools

## State Variables

### farmToken

```solidity
address public farmToken;
```

### tokenNum

```solidity
uint256 public tokenNum;
```

## Functions

### initialize

constructor

*\_cooldownPeriod = 0 Disables lockup functionality for the farm.*

```solidity
function initialize(
    uint256 _farmStartTime,
    uint256 _cooldownPeriod,
    address _farmToken,
    RewardTokenData[] memory _rwdTokenData
) external initializer;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_farmStartTime`|`uint256`|- time of farm start|
|`_cooldownPeriod`|`uint256`|- cooldown period for locked deposits in days|
|`_farmToken`|`address`|Address of the farm token|
|`_rwdTokenData`|`RewardTokenData[]`|- init data for reward tokens|

### deposit

Function is called when user transfers the NFT to the contract.

```solidity
function deposit(uint256 _amount, bool _lockup) external nonReentrant;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amount`|`uint256`|Amount of farmToken to be deposited|
|`_lockup`|`bool`|The lockup flag (bool).|

### increaseDeposit

Allow user to increase liquidity for a deposit

*User cannot increase liquidity for a deposit in cooldown*

```solidity
function increaseDeposit(uint8 _depositId, uint256 _amount) external nonReentrant;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_depositId`|`uint8`|Deposit index for the user.|
|`_amount`|`uint256`|Desired amount|

### decreaseDeposit

Withdraw liquidity partially from an existing deposit.

*Function is not available for locked deposits.*

```solidity
function decreaseDeposit(uint8 _depositId, uint256 _amount) external nonReentrant;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_depositId`|`uint8`|Deposit index for the user.|
|`_amount`|`uint256`|Amount to be withdrawn.|

### initiateCooldown

Function to lock a staked deposit

*\_depositId is corresponding to the user's deposit*

```solidity
function initiateCooldown(uint256 _depositId) external nonReentrant;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_depositId`|`uint256`|The id of the deposit to be locked|

### withdraw

Function to withdraw a deposit from the farm.

```solidity
function withdraw(uint256 _depositId) external nonReentrant;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_depositId`|`uint256`|The id of the deposit to be withdrawn|

### \_updateSubscriptionForIncrease

Update subscription data of a deposit for increase in liquidity.

```solidity
function _updateSubscriptionForIncrease(uint256 _tokenId, uint256 _amount) private;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|Unique token id for the deposit|
|`_amount`|`uint256`|Amount to be increased.|

### \_updateSubscriptionForDecrease

Update subscription data of a deposit after decrease in liquidity.

```solidity
function _updateSubscriptionForDecrease(uint256 _tokenId, uint256 _amount) private;
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|Unique token id for the deposit|
|`_amount`|`uint256`|Amount to be increased.|

## Events

### PoolFeeCollected

```solidity
event PoolFeeCollected(address indexed recipient, uint256 amt0Recv, uint256 amt1Recv);
```
