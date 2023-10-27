# IBalancerVault

[Git Source](https://github.com/Sperax/Demeter-Protocol/blob/fe40a3b3400612e06e8894e40f27c05bc3ec9a73/contracts/balancer/interfaces/IBalancerVault.sol)

## Functions

### getPool

```solidity
function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);
```

### getPoolTokens

```solidity
function getPoolTokens(bytes32 poolId)
    external
    view
    returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
```

## Enums

### PoolSpecialization

```solidity
enum PoolSpecialization {
    GENERAL,
    MINIMAL_SWAP_INFO,
    TWO_TOKEN
}
```
