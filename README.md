# [Demeter-Protocol](https://demeter.sperax.io/)

![plot](https://sperax.io/assets/working.88f515ef.png)

Works on Arbitrum Uniswap V3 and Camelot V2 <br />
Demeter protocol is a protocol for DAOs to launch and manage decentralized exchange liquidity - without needing to know how to code. Demeter gives users the power to launch incentivized liquidity pools on Uniswap V3 and Camelot V2. Future versions will support custom liquidity shapes on major DEXs such as Balancer, Saddle, Sushiswap or anything veSPA holders prefer. Demeter is launched on Arbitrum and will be expanded to Optimism, Polygon and Ethereum soon. Additional blockchains will be added in future versions.

## Contributing

Demeter is now open source and we are looking forward for your contributions!

If you’re interested in contributing please see our [contribution guidelines](./CONTRIBUTING.md).

## About Demeter

Demeter automates the fundamental aspects of launching and managing decentralized exchange liquidity for the DAOs native token:

- **Engineering support to launch and manage the farm** - The Audited Demeter Farm Factory contract will generate the pool and farm contracts for the Demeter user.
- **Marketing support to make the community aware of the new farm** - Protocols that launch their farm through Demeter benefit from being whitelisted on the Demeter active farms dashboard. This exclusive list features all of the farms that are actively distributing rewards that were deployed with Demeter. Farmers will regularly look to this dashboard for new projects and become users of these protocols.

### Launching Demeter Farm

1. Approve fee token to spend
1. Input pool parameters and farm parameters and execute a transaction to create farm and pay the farm creation fee
   1. If pool does not exist then the transaction reverts.
   1. If the user does not have enough fee tokens for fee payment then the transaction reverts. The fee is 100 USDs on Arbitrum.
1. After creation of the farm contract, reward token managers can update reward related parameters.
1. After creation of the farm contract, the farm admin can manage some attributes of the farm like start date, cooldown period, close/pause farm etc.

### Farm Parameters

1. Farm admin: It is the address that will have admin control on the farm. It can be the same as the deployer’s address or any other desired address which will be used to manage the farm.
1. Price range for the LP
1. Reward tokens
   - Token addresses
   - Token address managers; Each token will have its own token manager
   - Reward tokens have to be added at the time of farm creation and cant be added after the farm is created. Maximum 4 reward tokens are possible for a farm. SPA is added as a default reward token for       farms on Arbitrum and Ethereum networks. So for these networks, 3 additional reward tokens can be added by the farm creator.
1. Cooldown Period for Locked Liquidity - It is the number of days users have to wait after initiating cooldown before they can unstake from a locked position. Only whole numbers are allowed for this       parameter.
   - If Cooldown Period = 0, then the farm only allows creation of unlocked positions. Unlocked positions can be unstaked anytime.
   - If Cooldown Period > =1, the farm will allow creation of both locked and unlocked positions. For unstaking a locked position, users have to initiate cooldown and wait for cooldown period before
     unstaking. Farm
1. Start date time stamp - Reward emission starts from this date. This date can be changed by the farm admin using admin functions. However date change is not allowed after the farm starts.
   The farms start accepting liquidity immediately after the creation of the farm contract. However, the reward accrual starts from the farm start date time stamp.

### Fee

Demeter will charge a flat $100 fee to launch the farm. The fee collected belongs to the SPA stakers and can be transferred directly to the wallet address where all Sperax protocol fees are collected. Fees have to be paid in USDs on Arbitrum in the beginning, more payment methods can be added in future. Fee amount and fee token can be changed in future through governance.

### Farm Management

No one can make changes to the farm contract once deployed. Farm admins can do the following:

1. Transfer farm ownership to another address
1. Change start date of the farm - Farm will emit rewards from this date. The date can be changed after farm creation. However date change is not allowed after the farm starts.
1. Update cooldown period of the locked positions
1. Pause or Unpause the farm
   - **Pause the farm** - All reward distributions are paused, LPs do not earn any rewards during this period. Withdrawals are allowed (including lockup LPs) and users can also claim previously accrued rewards. Admin/managers can make changes to the distribution rates and the other parameters when the farm is paused.
   - **Unpause the farm** - Resume the reward distribution. The reward distribution rate remains the same as set by the reward managers.
1. Close the farm - Once the farm is closed, all liquidity providers including lockup users can now unstake their liquidity pool tokens and claim the accrued rewards from the farm

### Reward Management

Each reward token will be assigned a reward token manager. Farm admin cannot update the reward token manager once the farms are deployed. Reward token managers can do the following:

1. Add reward token balance
1. Update reward distribution rate per second for each token. Only future distribution rates can be affected through this. Reward distribution can be paused by setting the rate to 0. These actions can be done: For all liquidity providers For lockup liquidity providers (If cooldown period is greater than 0)
1. Withdraw reward tokens (Any rewards already accrued to LPs cannot be removed)
1. Transfer reward token management to another address

### Notes

- Protocols can call functions through non-EOA addresses and manage the farm. This is for multi-sigs or DAO’s to manage the pool and farm.
- SPA is added as a default reward token and protocols do not have the power to add or update the token reward manager for the SPA token. And the [Sperax-Gauge](https://app-v2.sperax.io/gauge) acts as the default token manager for SPA.
