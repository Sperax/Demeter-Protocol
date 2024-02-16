# Demeter_BalancerFarm_Deployer

[Git Source](https://github.com/Sperax/Demeter-Protocol/blob/fe40a3b3400612e06e8894e40f27c05bc3ec9a73/contracts/balancer/Demeter_BalancerFarm_Deployer.sol)

**Inherits:**
[FarmDeployer](/contracts/FarmDeployer.sol/contract.FarmDeployer.md), ReentrancyGuard

**Author:**
Sperax Foundation

This contract allows anyone to calculate fees and create farms

_It consults Balancer's vault to validate the pool_

## State Variables

### BALANCER_VAULT

```solidity
address public immutable BALANCER_VAULT;
```

### DEPLOYER_NAME

```solidity
string public DEPLOYER_NAME;
```

## Functions

### constructor

Constructor of the contract

_Deploys one farm so that it can be cloned later_

```solidity
constructor(address _registry, address _balancerVault, string memory _deployerName);
```

**Parameters**

| Name             | Type      | Description                              |
| ---------------- | --------- | ---------------------------------------- |
| `_registry`      | `address` | Address of Sperax Farm Registry          |
| `_balancerVault` | `address` | Address of Balancer's Vault              |
| `_deployerName`  | `string`  | String containing a name of the deployer |

### createFarm

Deploys a new Balancer farm.

_The caller of this function should approve feeAmount (USDs) for this contract_

```solidity
function createFarm(FarmData memory _data) external nonReentrant returns (address);
```

**Parameters**

| Name    | Type       | Description          |
| ------- | ---------- | -------------------- |
| `_data` | `FarmData` | data for deployment. |

**Returns**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `<none>` | `address` | Address of the new farm |

### calculateFees

An external function to calculate fees when pool tokens are in array.

```solidity
function calculateFees(IERC20[] memory _tokens) external view returns (address, address, uint256, bool);
```

**Parameters**

| Name      | Type       | Description                  |
| --------- | ---------- | ---------------------------- |
| `_tokens` | `IERC20[]` | Array of addresses of tokens |

**Returns**

| Name     | Type      | Description                                                             |
| -------- | --------- | ----------------------------------------------------------------------- |
| `<none>` | `address` | feeReceiver's address, feeToken's address, feeAmount, boolean claimable |
| `<none>` | `address` |                                                                         |
| `<none>` | `uint256` |                                                                         |
| `<none>` | `bool`    |                                                                         |

### validatePool

A function to validate Balancer pool

```solidity
function validatePool(bytes32 _poolId) public returns (address pool);
```

**Parameters**

| Name      | Type      | Description            |
| --------- | --------- | ---------------------- |
| `_poolId` | `bytes32` | bytes32 Id of the pool |

### \_calculateFees

An internal function to calculate fees when tokens are passed as an array

```solidity
function _calculateFees(IERC20[] memory _tokens) internal view returns (address, address, uint256, bool);
```

**Parameters**

| Name      | Type       | Description              |
| --------- | ---------- | ------------------------ |
| `_tokens` | `IERC20[]` | Array of token addresses |

**Returns**

| Name     | Type      | Description                                                             |
| -------- | --------- | ----------------------------------------------------------------------- |
| `<none>` | `address` | feeReceiver's address, feeToken's address, feeAmount, boolean claimable |
| `<none>` | `address` |                                                                         |
| `<none>` | `uint256` |                                                                         |
| `<none>` | `bool`    |                                                                         |

### \_collectFee

A function to collect the fees

```solidity
function _collectFee(IERC20[] memory _tokens) private;
```

**Parameters**

| Name      | Type       | Description              |
| --------- | ---------- | ------------------------ |
| `_tokens` | `IERC20[]` | Array of token addresses |

## Structs

### FarmData

```solidity
struct FarmData {
    address farmAdmin;
    uint256 farmStartTime;
    uint256 cooldownPeriod;
    bytes32 poolId;
    RewardTokenData[] rewardData;
}
```
