from brownie import (
    chain,
    accounts,
    UniswapFarmV1,
)

import pytest
import brownie
from conftest import (
    mint_position,
    GAS_LIMIT,
    deploy_uni_farm,
    init_farm,
    false_init_farm,
    fund_account,
    token_obj,
    constants,
    OWNER as owner,

)

# token_id1 = None
# token_id2 = None


farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']


def print_stats(farm, token_id):
    if(farm.cooldownPeriod() != 0):
        print('No-lockupFund: ', farm.rewardFunds(0))
        print('lockupFund: ', farm.rewardFunds(1))
        subs_name = ['no-lockup', 'lockup']
        for i in range(farm.getNumSubscriptions(token_id)):
            print(
                subs_name[i],
                ' deposit subscription : ',
                farm.subscriptions(token_id, i)
            )


@pytest.mark.parametrize('farm_name', farm_names)
def test_scenario_1(
    fn_isolation,
    farm_name,
    position_manager,
):
    # User creates a position in uniswap pool
    # User stakes the deposit in the farm with no-lockup
    # User claims the rewards
    # User withdraws the deposit
    global token_id1
    lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000001')
    no_lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000000')
    chain.snapshot()
    nftm = position_manager.address
    spa = token_obj('spa')
    usds = token_obj('usds')
    usdc = token_obj('usdc')
    frax = token_obj('frax')
    farm_config = constants()[farm_name]
    config = farm_config['config']

    farm = deploy_uni_farm(owner, UniswapFarmV1)
    print('Testing Initialization.....')
    with brownie.reverts('Invalid farm startTime'):
        false_init_farm(owner, farm, config)
    with brownie.reverts('Cooldown < MinCooldownPeriod'):
        print('Invalid Cooldown period.....')
        farm.initialize(

            brownie.chain.time()+1000,
            1,
            list(config['uniswap_pool_data'].values()),
            list(map(lambda x: list(x.values()), config['reward_token_data'])),
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
    with brownie.reverts('Invalid uniswap pool config'):
        farm.initialize(

            brownie.chain.time()+1000,
            86400,
            list(config['uniswap_pool_false_data'].values()),
            list(map(lambda x: list(x.values()), config['reward_token_data'])),
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )

    init_farm(owner, farm, config)
    print('Initialized Farm.....')

    with brownie.reverts('Time < now'):
        farm.updateFarmStartTime(brownie.chain.time()-1, {'from': owner})
    farm.updateFarmStartTime(brownie.chain.time()+2, {'from': owner})
    print('farm started.........')
    print('setup farm using invalid data.........')
    with brownie.reverts('Invalid reward data'):
        farm._setupFarm(5, [(brownie.ETH_ADDRESS, owner), (spa.address, owner),
                            (usds.address, owner),
                            (usdc, owner), (frax, owner)],
                        {'from': owner})
    # with brownie.reverts('Invalid reward data'):
    #     farm._setupFarm(5, [], {'from': owner})
    chain.snapshot()
    chain.mine(10, chain.time()+86400*7)
    chain.sleep(86400*7)
    with brownie.reverts('Farm already started'):
        farm.updateFarmStartTime(brownie.chain.time()+100, {'from': owner})

    reward_token = token_obj(farm_config['reward_token_A'])
    reward_token_1 = token_obj(farm_config['reward_token_B'])
    reward_token_2 = usdc
    token_a = token_obj(farm_config['token_A'])
    token_b = token_obj(farm_config['token_B'])
    # reward_token_dec = reward_token.decimals()
    token_a_dec = token_a.decimals()
    token_b_dec = token_b.decimals()
    fund_account(owner, 'usds', 2e23)
    fund_account(owner, 'spa', 2e23)
    fund_account(owner, 'usdc', 1e10)
    usds.approve(farm, 1e24, {'from': owner})
    spa.approve(farm, 1e24, {'from': owner})
    usdc.approve(farm, 1e12, {'from': owner})

    fund_account(accounts[1], 'usds', 2e23)
    fund_account(accounts[1], 'spa', 2e23)
    fund_account(accounts[1], 'usdc', 1e10)
    usds.approve(farm, 1e24, {'from': accounts[1]})
    spa.approve(farm, 1e24, {'from': accounts[1]})
    usdc.approve(farm, 1e12, {'from': accounts[1]})

    if (farm_name == 'test_farm_with_lockup'):

        tx = farm.getRewardBalance(usds, {'from': owner})
        print('balance of rewards is: ', tx)
    else:
        farm.getRewardBalance(usds, {'from': owner})

    tx = farm.addRewards(usds, 1e23, {'from': owner})
    tx = farm.addRewards(spa, 1e23, {'from': owner})
    tx = farm.addRewards(usdc, 1e10, {'from': owner})

    with brownie.reverts('Invalid _rwdToken'):
        farm.getRewardBalance(frax, {'from': owner})

    # User creates a position in uniswap pool
    # Register the token id
    token_id1 = mint_position(
        position_manager,
        token_a,
        token_b,
        config['uniswap_pool_data']['fee_tier'],
        config['uniswap_pool_data']['lower_tick'],
        config['uniswap_pool_data']['upper_tick'],
        1000 * 10 ** token_a_dec,
        1000 * 10 ** token_b_dec,
        owner,
    )

    token_id2 = mint_position(
        position_manager,
        token_a,
        token_b,
        config['uniswap_pool_data']['fee_tier'],
        config['uniswap_pool_data']['lower_tick'],
        config['uniswap_pool_data']['upper_tick'],
        2000 * 10 ** token_a_dec,
        2000 * 10 ** token_b_dec,
        accounts[1],
    )
    liquidity = farm._getLiquidity(token_id1, {'from': owner})

    with brownie.reverts('Invalid fund id'):
        farm._subscribeRewardFund(2, token_id1, liquidity, {'from': owner})

    # Get position details
    position = position_manager.positions(token_id1)
    position2 = position_manager.positions(token_id2)
    print('User position: ', position)
    with brownie.reverts('Reward token already added'):
        farm._addRewardData(spa, owner, {'from': owner})

    # check the initial number of deposit for the user.
    farm.getNumDeposits(owner)

    # It's a no-lockup deposit
    print('\n ----Depositing in Farm---- ')

    if (farm_name == 'test_farm_with_lockup'):
        deposit_txn = position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            lock_data,
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
        position_manager.safeTransferFrom(
            accounts[1],
            farm.address,
            token_id2,
            no_lock_data,
            {'from': accounts[1], 'gas_limit': GAS_LIMIT},
        )
        assert farm.rewardFunds(0) == position[7]+position2[7]
        assert farm.getNumSubscriptions(token_id1) == 2
    # assert farm.getNumDeposits(owner) == num_deposits + 2
    if (farm_name == 'test_farm_without_lockup'):

        with brownie.reverts('Lockup functionality is disabled'):
            farm.onERC721Received(
                accounts[2],
                owner,
                token_id2,
                lock_data,
                {'from': nftm, 'gas_limit': GAS_LIMIT},
            )
        deposit_txn = position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            no_lock_data,
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
        assert farm.getNumSubscriptions(token_id1) == 1
        assert farm.rewardFunds(0) == position[7]
    print_stats(farm, token_id1)
    print_stats(farm, token_id2)

    assert deposit_txn.events['Deposited']['account'] == owner
    assert deposit_txn.events['Deposited']['tokenId'] == token_id1

    # Should have only one subscription for the no-lockup deposit

    farm._getAccRewards(0, 0, 1e10)
    if (farm_name == 'test_farm_with_lockup'):
        farm.setRewardRate(usds, [1e15, 2e15], {'from': owner})
        farm.setRewardRate(spa, [1e15, 2e15], {'from': owner})
        farm.setRewardRate(usdc, [1e3, 2e3], {'from': owner})
        print('reward funds LockUp: ', farm.rewardFunds(0))
    elif (farm_name == 'test_farm_without_lockup'):
        farm.setRewardRate(usds, [1e15], {'from': owner})
        farm.setRewardRate(spa, [1e15], {'from': owner})
        farm.setRewardRate(usdc, [1e3], {'from': owner})
    # no-lockup reward fund should be updated
        print('reward funds Non LockUp: ', farm.rewardFunds(0))

    # Move ahead in time.
    chain.mine(10, None, 86400)

    balance = reward_token.balanceOf(owner)
    balance_usds = reward_token_1.balanceOf(owner)
    balance_usdc = reward_token_2.balanceOf(owner)
    print('\n ----Invalid Subscription---- ')
    with brownie.reverts('Subscription does not exist'):
        farm.getSubscriptionInfo(token_id1, 3)
    with brownie.reverts('Invalid fund id'):
        farm._unsubscribeRewardFund(2, owner, 0, {'from': owner})
    reward_info = farm.getRewardFundInfo(0)
    print('reward funds are: ', reward_info)
    with brownie.reverts('Reward fund does not exist'):
        farm.getRewardFundInfo(10)
    print('\n ----Claiming rewards---- ')

    claim_txn = farm.claimRewards(0, {'from': owner, 'gas_limit': GAS_LIMIT})

    r0 = claim_txn.events['RewardsClaimed']
    print_stats(farm, token_id1)
    # print('Rewards Claimed: ', r0)
    print('Asserting Claimed Rewards.....')
    if (farm_name == 'test_farm_with_lockup'):
        r0_0 = r0[0]['rewardAmount']
        r0_1 = r0[1]['rewardAmount']

        assert r0_0[0]+r0_1[0] - (reward_token.balanceOf(owner) - balance) < 2
        assert r0_0[1] + \
            r0_1[1] - (reward_token_1.balanceOf(owner) - balance_usds) < 2
        assert r0_0[2] + \
            r0_1[2] == (reward_token_2.balanceOf(owner) - balance_usdc)
        print('SPA Reward claimed: ', (r0_0[0]+r0_1[0])/1e18)
        print('USDs Reward claimed: ', (r0_0[1]+r0_1[1])/1e18)
        print('USDC Reward claimed: ', (r0_0[2]+r0_1[2])/1e6)
    elif (farm_name == 'test_farm_without_lockup'):
        r0_0 = r0[0]['rewardAmount']
        assert r0_0[0] - (reward_token.balanceOf(owner) - balance) >= 0 and (
            r0_0[0] - (reward_token.balanceOf(owner) - balance)) < 2
        assert r0_0[1] - (reward_token_1.balanceOf(
            owner) - balance_usds) >= -2 and r0_0[1] - \
            (reward_token_1.balanceOf(owner) - balance_usds) < 2
        assert r0_0[2] == (reward_token_2.balanceOf(owner) - balance_usdc)
        print('SPA Reward claimed: ', r0_0[0]/1e18)
        print('USDs Reward claimed: ', r0_0[1]/1e18)
        print('USDC Reward claimed: ', r0_0[2]/1e6)
        # Try to initiate a cooldown for no-lockup deposit.
        with brownie.reverts('Can not initiate cooldown'):
            farm.initiateCooldown(
                0,
                {'from': owner, 'gas_limit': GAS_LIMIT}
            )
    print('Claimed Rewards Looks Correct..... 😀 ')
    r0 = claim_txn.events['RewardsClaimed']['rewardAmount']
    # Reward Token 1
    assert farm.getSubscriptionInfo(token_id1, 0)[1][0] == r0[0]
    # Reward Token 2
    assert farm.getSubscriptionInfo(token_id1, 0)[1][1] == r0[1]

    # Move ahead in time.
    chain.mine(10, None, 86400)
    # Withdraw the deposit
    print('\n ----Withdrawing the deposit---- ')

    print('\n ----Farm is Paused---- ')
    with brownie.reverts('Farm already in required state'):
        farm.farmPauseSwitch(False, {'from': owner})
    chain.mine(10, None, 86400)
    farm.farmPauseSwitch(True, {'from': owner})
    farm._updateFarmRewardData({'from': owner})

    with brownie.reverts('Invalid address'):
        farm._ensureItsNonZeroAddr(brownie.ZERO_ADDRESS, {'from': owner})
    if(farm_name == 'test_farm_with_lockup'):
        withdraw_txn = farm.withdraw(
            0, {'from': accounts[1], 'gas_limit': GAS_LIMIT})
        subscription = farm.getNumSubscriptions(token_id2)
        assert subscription == 0
    farm._updateFarmRewardData({'from': owner})
    farm.farmPauseSwitch(False, {'from': owner})
    chain.undo(2)
    print('\n ----Farm is running---- ')
    withdraw_txn = farm.withdraw(0, {'from': owner, 'gas_limit': GAS_LIMIT})
    print_stats(farm, token_id1)
    r0 = claim_txn.events['RewardsClaimed']
    r1 = withdraw_txn.events['RewardsClaimed']

    if (farm_name == 'test_farm_with_lockup'):
        r0_0 = r0[0]['rewardAmount']
        r0_1 = r0[1]['rewardAmount']
        r1_0 = r1[0]['rewardAmount']
        r1_1 = r1[1]['rewardAmount']
        w_e = withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed']
        assert w_e[0] == r0_0[0] + r1_0[0]+r0_1[0] + r1_1[0]
        assert w_e[1] == r0_0[1] + r1_0[1]+r0_1[1] + r1_1[1]
        assert w_e[2] == r0_0[2] + r1_0[2] + r0_1[2] + r1_1[2]
        print('SPA Withdrawn Reward : ',
              (r0_0[0] + r1_0[0]+r0_1[0] + r1_1[0])/1e18)
        print('USDs Withdrawn Reward: ',
              (r0_0[1]+r1_0[1]+r0_1[1] + r1_1[1])/1e18)
        print('USDC Withdrawn Reward : ',
              (r0_0[2]+r1_0[2] + r0_1[2] + r1_1[2])/1e6)

    elif (farm_name == 'test_farm_without_lockup'):
        r0_0 = r0[0]['rewardAmount']
        r1_0 = r1[0]['rewardAmount']
        w_e = withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed']
        assert w_e[0] == r0_0[0] + r1_0[0]
        assert w_e[1] == r0_0[1] + r1_0[1]
        assert w_e[2] == r0_0[2] + r1_0[2]
        print('SPA Withdrawn Reward : ', (r0_0[0] + r1_0[0])/1e18)
        print('USDs Withdrawn Reward: ', (r0_0[1] + r1_0[1])/1e18)
        print('USDC Withdrawn Reward : ', (r0_0[2]+r1_0[2])/1e6)
    print('Withdrawn Reward Check Completed 💪💪💪💪')
    # assert isclose(reward_token.balanceOf(owner),
    #                balance + r0[0] + r1[0]+2, rel_tol=1e-18)
    farm.recoverRewardFunds(usds, farm.getRewardBalance(
        usds, {'from': owner}), {'from': owner})
    tx = farm.getRewardBalance(usds, {'from': owner})
    print('after rewards recovered balance: ', tx)
    assert farm.getNumDeposits(owner) == 0
    # farm.recoverERC20(usds, {'from': owner})
    with brownie.reverts("Can't withdraw 0 amount"):
        farm.recoverERC20(frax, {'from': owner})
    with brownie.reverts("Can't withdraw rewardToken"):
        farm.recoverERC20(usds, {'from': owner})
    fund_account(farm, 'frax', 1e19)
    farm.recoverERC20(frax, {'from': owner})
    farm.recoverRewardFunds(spa, 0, {'from': owner})
    print('Testing False Tick ranges......')
    with brownie.reverts('Invalid tick range'):
        farm._validateTickRange(-887220, -887220)
    with brownie.reverts('Invalid tick range'):
        farm._validateTickRange(-887273, 887210)
    with brownie.reverts('Invalid tick range'):
        farm._validateTickRange(-887219, 887210)
    with brownie.reverts('Invalid tick range'):
        farm._validateTickRange(-887220, 887273)
    with brownie.reverts('Invalid tick range'):
        farm._validateTickRange(-887220, 887219)
    with brownie.reverts('Incorrect pool token'):
        farm._getLiquidity(117684)

    farm._getAccRewards(0, 0, 1e10)
    chain.revert()


@pytest.mark.parametrize('farm_name', farm_names)
def test_scenario_2(
    fn_isolation,
    farm_name,
    position_manager,
):
    lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000001')
    no_lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000000')
    spa = token_obj('spa')
    usds = token_obj('usds')
    usdc = token_obj('usdc')
    farm_config = constants()[farm_name]
    config = farm_config['config']

    farm = deploy_uni_farm(owner, UniswapFarmV1)
    init_farm(owner, farm, config)

    # reward_token = token_obj(farm_config['reward_token_A'])
    # reward_token_1 = token_obj(farm_config['reward_token_B'])
    token_a = token_obj(farm_config['token_A'])
    token_b = token_obj(farm_config['token_B'])
    token_a_dec = token_a.decimals()
    token_b_dec = token_b.decimals()
    fund_account(owner, 'usds', 2e23)
    fund_account(owner, 'spa', 2e23)
    fund_account(owner, 'usdc', 1e10)
    usds.approve(farm, 1e24, {'from': owner})
    spa.approve(farm, 1e24, {'from': owner})
    usdc.approve(farm, 1e12, {'from': owner})

    tx = farm.addRewards(usds, 1e23, {'from': owner})
    tx = farm.addRewards(spa, 1e23, {'from': owner})
    tx = farm.addRewards(usdc, 1e10, {'from': owner})

    if (farm_name == 'test_farm_with_lockup'):
        farm.setRewardRate(usds, [1e15, 2e15], {'from': owner})
        farm.setRewardRate(spa, [1e15, 2e15], {'from': owner})
        farm.setRewardRate(usdc, [1e3, 2e3], {'from': owner})
    elif (farm_name == 'test_farm_without_lockup'):
        farm.setRewardRate(usds, [1e15], {'from': owner})
        farm.setRewardRate(spa, [1e15], {'from': owner})
        farm.setRewardRate(usdc, [1e3], {'from': owner})

    token_id1 = mint_position(
        position_manager,
        token_a,
        token_b,
        config['uniswap_pool_data']['fee_tier'],
        config['uniswap_pool_data']['lower_tick'],
        config['uniswap_pool_data']['upper_tick'],
        1000 * 10 ** token_a_dec,
        1000 * 10 ** token_b_dec,
        owner,
    )

    token_id3 = mint_position(
        position_manager,
        token_a,
        token_b,
        config['uniswap_pool_data']['fee_tier'],
        -20400,
        -16020,
        1000 * 10 ** token_a_dec,
        1000 * 10 ** token_b_dec,
        owner,
    )
    token_id4 = mint_position(
        position_manager,
        token_a,
        token_b,
        config['uniswap_pool_data']['fee_tier'],
        config['uniswap_pool_data']['lower_tick'],
        -16020,
        1000 * 10 ** 18,
        1000 * 10 ** 18,
        owner,
    )

    # check the initial number of deposit for the user.
    num_deposits = farm.getNumDeposits(owner)

    # Get position details
    position = position_manager.positions(token_id1)

    # print('\n ----Invalid Deposit : not a SPAUSDs Token----')
    # with brownie.reverts("Incorrect pool token"):
    #     position_manager.safeTransferFrom(
    #         owner,
    #         farm.address,
    #         token_id2,
    #         '0x0000000000000000000000000000000000000000000000000000000000000001',
    #         {'from': owner, 'gas_limit': GAS_LIMIT},
    #     )

    # print('\n ----Invalid Deposit : incorrect tick range----')
    if (farm_name == 'test_farm_with_lockup'):
        with brownie.reverts('Incorrect tick range'):
            position_manager.safeTransferFrom(
                owner,
                farm.address,
                token_id3,
                lock_data,
                {'from': owner, 'gas_limit': GAS_LIMIT},
            )
        with brownie.reverts('Incorrect tick range'):
            position_manager.safeTransferFrom(
                owner,
                farm.address,
                token_id4,
                lock_data,
                {'from': owner, 'gas_limit': GAS_LIMIT},
            )

    # print('\n ----Invalid Deposit----')
    with brownie.reverts('onERC721Received: no data'):
        position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )

    print('\n ----Depositing in Farm---- ')
    # It's a lockup deposit
    if (farm_name == 'test_farm_with_lockup'):
        deposit_txn = position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            lock_data,
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
    elif (farm_name == 'test_farm_without_lockup'):
        deposit_txn = position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            no_lock_data,
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
        computed_rewards = farm.computeRewards(owner, 0)
        computed_rewards = farm.computeRewards(owner, 0)
        with brownie.reverts('onERC721Received: not a univ3 nft'):
            farm.onERC721Received(
                accounts[2],
                owner,
                token_id1,
                no_lock_data,
                {'from': owner, 'gas_limit': GAS_LIMIT},
            )
    print_stats(farm, token_id1)
    #  if (farm_name == 'test_farm_with_lockup'):
    assert farm.getNumDeposits(owner) == num_deposits + 1

    assert deposit_txn.events['Deposited']['account'] == owner
    assert deposit_txn.events['Deposited']['tokenId'] == token_id1

    # Should have two subscriptions for the lockup deposit
    if (farm_name == 'test_farm_with_lockup'):
        assert farm.getNumSubscriptions(token_id1) == 2
    else:
        assert farm.getNumSubscriptions(token_id1) == 1

    # no-lockup reward fund should be updated
    assert farm.rewardFunds(0) == position[7]

    # claim rewards for wrong deposit
    with brownie.reverts('Deposit does not exist'):
        farm.claimRewards(
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )
    with brownie.reverts('Deposit does not exist'):
        farm.claimRewards(
            owner,
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Move ahead in time.
    chain.mine(10, None, 86400)
    # balance = reward_token.balanceOf(owner)
    # balance_usds = reward_token_1.balanceOf(owner)
    total_rewards = 0

    print('\n ------Claiming rewards---- ')
    with brownie.reverts('Deposit does not exist'):
        farm.computeRewards(owner, 3)
    computed_rewards = farm.computeRewards(owner, 0)
    claim_txn = farm.claimRewards(
        owner,
        0,
        {'from': owner, 'gas_limit': GAS_LIMIT}
    )
    print_stats(farm, token_id1)

    print('Computed Rewards: ', computed_rewards)

    if (farm_name == 'test_farm_with_lockup'):
        r0 = claim_txn.events['RewardsClaimed'][0]['rewardAmount'] + \
            claim_txn.events['RewardsClaimed'][1]['rewardAmount']
        print('Rewards Claimed: ', r0)
        # assert reward_token.balanceOf(owner) - balance-(r0[0]+r0[2]) < 3
        # assert isclose(r0[1]+r0[3], reward_token_1.balanceOf(owner) - \
        # balance_usds, rel_tol=1e-18)
        total_rewards += r0[0]+r0[2]
    else:
        r0 = claim_txn.events['RewardsClaimed'][0]['rewardAmount']
        print('Rewards Claimed: ', r0)
        # assert reward_token.balanceOf(owner) - balance-(r0[0]) < 3
        # assert isclose(r0[1], reward_token_1.balanceOf(owner) - balance_usds,
        #  rel_tol=1e-18)
        total_rewards += r0[0]
    print('\n ----Claiming rewards After recovering funds--- ')
    farm.recoverRewardFunds(usds, farm.getRewardBalance(
        usds, {'from': owner}), {'from': owner})
    farm.recoverRewardFunds(spa, farm.getRewardBalance(
        spa, {'from': owner}), {'from': owner})
    computed_rewards = farm.computeRewards(owner, 0)
    tx = farm.getRewardBalance(usds, {'from': owner})
    tx2 = farm.getRewardBalance(spa, {'from': owner})
    print('after rewards recovered balance: USDs: ', tx, ' SPA: ', tx2)
    computed_rewards = farm.computeRewards(owner, 0)
    print('Computed Rewards after recovering funds before claiming: ',
          computed_rewards)
    claim_txn = farm.claimRewards(
        owner,
        0,
        {'from': owner, 'gas_limit': GAS_LIMIT}
    )
    print_stats(farm, token_id1)
    computed_rewards = farm.computeRewards(owner, 0)
    print('Computed Rewards after recovering funds after claiming: ',
          computed_rewards)
    if (farm_name == 'test_farm_with_lockup'):
        rr = claim_txn.events['RewardsClaimed'][0]['rewardAmount'] + \
            claim_txn.events['RewardsClaimed'][1]['rewardAmount']
        print('Rewards Claimed after recovered funds: ', rr)
        # assert reward_token.balanceOf(
        #    owner) - balance-(r0[0]+r0[2]+rr[0]+rr[2]) < 3
        # assert isclose(r0[1]+r0[3], reward_token_1.balanceOf(owner) - \
        #  balance_usds-rr[2], rel_tol=1e-18)
        total_rewards += rr[0]+rr[2]
    else:
        rr = claim_txn.events['RewardsClaimed'][0]['rewardAmount']
        print('Rewards Claimed after recovered funds: ', rr)
        # assert reward_token.balanceOf(owner) - balance-(r0[0]) < 3
        # assert isclose(r0[1], reward_token_1.balanceOf(owner) - balance_usds,
        #  rel_tol=1e-18)
        total_rewards += rr[0]
    # Withdraw the deposit without initiating cooldown
    print('\n ----Withdrawing the deposit without cooldown---- ')
    if (farm_name == 'test_farm_with_lockup'):
        with brownie.reverts('Please initiate cooldown'):
            farm.withdraw(
                0,
                {'from': owner, 'gas_limit': GAS_LIMIT}
            )

    # Try to initiate a cooldown for wrong deposit
    with brownie.reverts('Deposit does not exist'):
        farm.initiateCooldown(
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # # Move ahead in time.
    # chain.mine(10, None, 1000)
    if (farm_name == 'test_farm_with_lockup'):
        print('\n ----Initiating cooldown---- ')
        initiate_cooldown_txn = farm.initiateCooldown(
            0,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )
        print_stats(farm, token_id1)
        r1 = initiate_cooldown_txn.events['RewardsClaimed'][0]['rewardAmount']\
            + initiate_cooldown_txn.events['RewardsClaimed'][1]['rewardAmount']
        print(
            'Rewards Claimed: ',
            r1
        )

        # if (farm_name == 'test_farm_with_lockup'):
        #     total_rewards += r1[0]+r1[2]
        #     assert isclose(reward_token.balanceOf(owner),
        #                    balance + r1[0] + r1[2], rel_tol=0.001)
        # else:
        #     total_rewards += r1[0]
        #     assert isclose(reward_token.balanceOf(owner),
        #                    balance + r1[0], rel_tol=0.001)
    # Try to initiate a cooldown for a deposit already in cooldown
    with brownie.reverts('Can not initiate cooldown'):
        farm.initiateCooldown(
            0,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Withdraw during the cooldown period
    if (farm_name == 'test_farm_with_lockup'):
        print('\n ----Withdrawing the deposit without cooldown---- ')
        with brownie.reverts('Deposit is in cooldown'):
            farm.withdraw(
                0,
                {'from': owner, 'gas_limit': GAS_LIMIT}
            )

    # Try to withdraw for wrong deposit
    with brownie.reverts('Deposit does not exist'):
        farm.withdraw(
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    tx = farm.getRewardBalance(usds, {'from': owner})
    tx = farm.getRewardBalance(spa, {'from': owner})

    # Move ahead in time.
    chain.mine(10, farm.deposits(owner, 0)[4])

    # Withdraw the deposit
    print('\n ----Withdrawing the deposit---- ')
    computed_rewards = farm.computeRewards(owner, 0)
    computed_rewards = farm.computeRewards(owner, 0)
    withdraw_txn = farm.withdraw(0, {'from': owner, 'gas_limit': GAS_LIMIT})
    print_stats(farm, token_id1)
    r2 = withdraw_txn.events['RewardsClaimed']['rewardAmount']
    print('Rewards Claimed: ', r2)
    total_rewards += r2[0]
    # assert total_rewards == \
    #     withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][0]
    # assert
    # withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][1] == \
    # r2[1]

    # assert reward_token.balanceOf(owner) - \
    #     (balance + total_rewards) < 6
    assert farm.getNumDeposits(owner) == 0

    if (farm_name == 'test_farm_with_lockup'):
        with brownie.reverts('Cooldown period too low'):
            farm.updateCooldownPeriod(1,
                                      {'from': owner, 'gas_limit': GAS_LIMIT})
        farm.updateCooldownPeriod(86400*3,
                                  {'from': owner, 'gas_limit': GAS_LIMIT})
        farm.setRewardRate(spa.address, [1000, 2000],
                           {'from': owner, 'gas_limit': GAS_LIMIT})

    else:
        with brownie.reverts('Farm does not support lockup'):
            farm.updateCooldownPeriod(86400*3,
                                      {'from': owner, 'gas_limit': GAS_LIMIT})
        with brownie.reverts('Invalid reward rates length'):
            farm.setRewardRate(spa.address, [1000, 2000],
                               {'from': owner, 'gas_limit': GAS_LIMIT})

    chain.revert()
