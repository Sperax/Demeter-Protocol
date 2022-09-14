from brownie import (
    chain,
    accounts,
    Farm,
    UniswapFarmV1,
)
import pytest
import brownie
from math import isclose
from conftest import (
    mint_position,
    GAS_LIMIT,
    deploy,
    deploy_uni_farm,
    init_farm,
    false_init_farm,
    fund_account,
    owner,
    constants,
    token_obj,

)

token_id1 = None
token_id2 = None


farm_names = ['test_farm_without_lockup', 'test_farm_with_lockup']


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
    nftm = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
    spa = token_obj('spa')
    usds = token_obj('usds')
    usdc = token_obj('usdc')
    farm_config = constants[farm_name]
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
    reward_token = token_obj(farm_config['reward_token_A'])
    reward_token_1 = token_obj(farm_config['reward_token_B'])
    token_a = token_obj(farm_config['token_A'])
    token_b = token_obj(farm_config['token_B'])
    # reward_token_dec = reward_token.decimals()
    token_a_dec = token_a.decimals()
    token_b_dec = token_b.decimals()
    fund_account(owner, 'usds', 2e23)
    fund_account(owner, 'spa', 2e23)
    usds.approve(farm, 1e24, {'from': owner})
    spa.approve(farm, 1e24, {'from': owner})
    if (farm_name == 'test_farm_with_lockup'):

        tx = farm.getRewardBalance(usds, {'from': owner})
        print('balance of rewards is: ', tx)
    else:
        farm.getRewardBalance(usds, {'from': owner})
    farm.addRewards(usds, 1e23, {'from': owner})
    farm.addRewards(spa, 1e23, {'from': owner})
    with brownie.reverts('Invalid _rwdToken'):
        farm.getRewardBalance(usdc, {'from': owner})

    farm.recoverRewardFunds(spa, 0, {'from': owner})

    # For Generic Farm Scenario
    # fund_account(
    #     farm,
    #     farm_config['reward_token'],
    #     1e7 * 10 ** reward_token_dec
    # )
    # fund_account(owner, farm_config['token_A'],  5e4 * 10 ** token_a_dec)
    # fund_account(owner, farm_config['token_B'],  5e4 * 10 ** token_b_dec)

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
    liquidity = farm._getLiquidity(token_id1, {'from': owner})
    with brownie.reverts('Invalid fund id'):
        farm._subscribeRewardFund(2, token_id1, liquidity, {'from': owner})

    # Get position details
    position = position_manager.positions(token_id1)
    print('User position: ', position)
    chain.snapshot()

    # check the initial number of deposit for the user.
    num_deposits = farm.getNumDeposits(owner)
    # with brownie.reverts
    # ('UniswapV3Staker::onERC721Received: not a univ3 nft'):
    #     farm.onERC721Received(
    #         accounts[2],
    #         owner,
    #         token_id1,
    #         '0x0000000000000000000000000000000000000000000000000000000000000000',
    #         {'from': nftm, 'gas_limit': GAS_LIMIT},
    #     )
    # Successful deposit test
    # It's a no-lockup deposit
    print('\n ----Depositing in Farm---- ')
    deposit_txn = position_manager.safeTransferFrom(
        owner,
        farm.address,
        token_id1,
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        {'from': owner, 'gas_limit': GAS_LIMIT},
    )
    lock_data = '0x0000000000000000000000000000000000000000000000000000000000000001'
    if(farm_name == 'test_farm_without_lockup'):

        with brownie.reverts('Lockup functionality is disabled'):
            farm.onERC721Received(
                accounts[2],
                owner,
                token_id1,
                lock_data,
                {'from': nftm, 'gas_limit': GAS_LIMIT},
            )
    print_stats(farm, token_id1)
    assert farm.getNumDeposits(owner) == num_deposits + 1
    assert deposit_txn.events['Deposited']['account'] == owner
    assert deposit_txn.events['Deposited']['tokenId'] == token_id1

    # Should have only one subscription for the no-lockup deposit
    assert farm.getNumSubscriptions(token_id1) == 1

    # no-lockup reward fund should be updated
    # print("reward funds: ",farm.rewardFunds(0)[0],
    # 'uniswap position: ',position)
    assert farm.rewardFunds(0) == position[7]

    # Move ahead in time.
    chain.mine(10, chain.time() + 1000)

    balance = reward_token.balanceOf(owner)
    balance_usds = reward_token_1.balanceOf(owner)
    print('\n ----Invalid Subscription---- ')
    with brownie.reverts('Subscription does not exist'):
        farm.getSubscriptionInfo(token_id1, 3)

    with brownie.reverts('Invalid fund id'):
        farm._unsubscribeRewardFund(2, owner, 0, {'from': owner})

    print('\n ----Claiming rewards---- ')
    claim_txn = farm.claimRewards(0, {'from': owner, 'gas_limit': GAS_LIMIT})
    print_stats(farm, token_id1)
    r0 = claim_txn.events['RewardsClaimed']['rewardAmount']
    print('Rewards Claimed: ', r0)
    assert r0[0]-(reward_token.balanceOf(owner) - balance) < 3   # noqa
    assert r0[1] == reward_token_1.balanceOf(owner) - balance_usds  # noqa
    print('claim both rewards passed')
    # Reward Token 1
    assert farm.getSubscriptionInfo(token_id1, 0)[1][0] == r0[0]
    # Reward Token 2
    assert farm.getSubscriptionInfo(token_id1, 0)[1][1] == r0[1]

    # Try to initiate a cooldown for no-lockup deposit.
    with brownie.reverts('Can not initiate cooldown'):
        txn = farm.initiateCooldown(  # noqa
            0,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Move ahead in time.
    chain.mine(10, chain.time() + 1000)
    # Withdraw the deposit
    print('\n ----Withdrawing the deposit---- ')
    withdraw_txn = farm.withdraw(0, {'from': owner, 'gas_limit': GAS_LIMIT})
    print_stats(farm, token_id1)
    r1 = withdraw_txn.events['RewardsClaimed']['rewardAmount']
    print('Rewards Claimed: ', r1)
    assert withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][0] == r0[0] + r1[0]
    assert withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][1] == r0[1] + r1[1]   # noqa

    assert isclose(reward_token.balanceOf(owner),
                   balance + r0[0] + r1[0]+2, rel_tol=1e-18)
    # farm.recoverRewardFunds(usds,farm.getRewardBalance(usds, {'from': owner}), {'from': owner})
    # tx=farm.getRewardBalance(usds, {'from': owner})
    # print("after rewards recovered balance: ",tx)
    assert farm.getNumDeposits(owner) == 0

    chain.revert()


@pytest.mark.parametrize('farm_name', farm_names)
def test_scenario_2(
    fn_isolation,
    farm_name,
    position_manager,
):

    # User creates a position in uniswap pool
    # # Register the token id
    # token_id2 = mint_position(
    #     position_manager,
    #     usds,
    #     usdc,
    #     fee3,
    #     lower_tick,
    #     upper_tick,
    #     100000,
    #     100000,
    #     owner,
    spa = token_obj('spa')
    usds = token_obj('usds')
    farm_config = constants[farm_name]
    config = farm_config['config']
    farm = deploy_uni_farm(owner, UniswapFarmV1)
    init_farm(owner, farm, config)

    reward_token = token_obj(farm_config['reward_token_A'])
    reward_token_1 = token_obj(farm_config['reward_token_B'])
    token_a = token_obj(farm_config['token_A'])
    token_b = token_obj(farm_config['token_B'])
    token_a_dec = token_a.decimals()
    token_b_dec = token_b.decimals()
    fund_account(owner, 'usds', 2e23)
    fund_account(owner, 'spa', 2e23)

    usds.approve(farm, 1e24, {'from': owner})
    spa.approve(farm, 1e24, {'from': owner})

    farm.addRewards(usds, 1e23, {'from': owner})
    farm.addRewards(spa, 1e23, {'from': owner})

    # fund_account(
    #     farm,
    #     farm_config['reward_token'],
    #     1e7 * 10 ** reward_token_dec
    # )
    # fund_account(owner, farm_config['token_A'],  5e4 * 10 ** token_a_dec)
    # fund_account(owner, farm_config['token_B'],  5e4 * 10 ** token_b_dec)

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
        1000 * 10 ** token_a_dec,
        1000 * 10 ** token_b_dec,
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
    #         '0x0000000000000000000000000000000000000000000000000000000000000001',  # noqa
    #         {'from': owner, 'gas_limit': GAS_LIMIT},
    #     )

    # print('\n ----Invalid Deposit : incorrect tick range----')
    if (farm_name == 'test_farm_with_lockup'):
        with brownie.reverts('Incorrect tick range'):
            position_manager.safeTransferFrom(
                owner,
                farm.address,
                token_id3,
                '0x0000000000000000000000000000000000000000000000000000000000000001',  # noqa
                {'from': owner, 'gas_limit': GAS_LIMIT},
            )
        with brownie.reverts('Incorrect tick range'):
            position_manager.safeTransferFrom(
                owner,
                farm.address,
                token_id4,
                '0x0000000000000000000000000000000000000000000000000000000000000001',  # noqa
                {'from': owner, 'gas_limit': GAS_LIMIT},
            )

    # if (farm_name == 'test_farm_without_lockup'):
    #     position_manager.safeTransferFrom(
    #         accounts[2],
    #         owner,
    #         token_id1,
    #         '0x0000000000000000000000000000000000000000000000000000000000000001',
    #         {'from': owner, 'gas_limit': GAS_LIMIT},
    #     )
    # print('\n ----Invalid Deposit----')
    with brownie.reverts('UniswapV3Staker::onERC721Received: no data'):
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
            '0x0000000000000000000000000000000000000000000000000000000000000001',
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
    elif (farm_name == 'test_farm_without_lockup'):
        deposit_txn = position_manager.safeTransferFrom(
            owner,
            farm.address,
            token_id1,
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            {'from': owner, 'gas_limit': GAS_LIMIT},
        )
        with brownie.reverts('UniswapV3Staker::onERC721Received: not a univ3 nft'):
            farm.onERC721Received(
                accounts[2],
                owner,
                token_id1,
                '0x0000000000000000000000000000000000000000000000000000000000000000',
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
        txn = farm.claimRewards(  # noqa
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )
    with brownie.reverts('Deposit does not exist'):
        txn = farm.claimRewards(  # noqa
            owner,
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Move ahead in time.
    chain.mine(10, chain.time() + 1000)
    balance = reward_token.balanceOf(owner)
    balance_usds = reward_token_1.balanceOf(owner)
    total_rewards = 0

    print('\n ----Claiming rewards---- ')
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
        assert reward_token.balanceOf(owner) - balance-(r0[0]+r0[2]) < 3  # noqa
        assert isclose(r0[1]+r0[3], reward_token_1.balanceOf(owner) - balance_usds, rel_tol=1e-18)  # noqa
        total_rewards += r0[0]+r0[2]
    else:
        r0 = claim_txn.events['RewardsClaimed'][0]['rewardAmount']
        print('Rewards Claimed: ', r0)
        assert reward_token.balanceOf(owner) - balance-(r0[0]) < 3  # noqa
        assert isclose(r0[1], reward_token_1.balanceOf(owner) - balance_usds, rel_tol=1e-18)  # noqa
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
    print('Computed Rewards after recovering funds before claiming: ', computed_rewards)
    claim_txn = farm.claimRewards(
        owner,
        0,
        {'from': owner, 'gas_limit': GAS_LIMIT}
    )
    print_stats(farm, token_id1)
    computed_rewards = farm.computeRewards(owner, 0)
    print('Computed Rewards after recovering funds after claiming: ', computed_rewards)
    if (farm_name == 'test_farm_with_lockup'):
        rr = claim_txn.events['RewardsClaimed'][0]['rewardAmount'] + \
            claim_txn.events['RewardsClaimed'][1]['rewardAmount']
        print('Rewards Claimed after recovered funds: ', rr)
        # assert reward_token.balanceOf(owner) - balance-(r0[0]+r0[2]+rr[0]+rr[2])<3  # noqa
        # assert isclose(r0[1]+r0[3], reward_token_1.balanceOf(owner) - balance_usds-rr[2],rel_tol=1e-18) # noqa
        total_rewards += rr[0]+rr[2]
    else:
        rr = claim_txn.events['RewardsClaimed'][0]['rewardAmount']
        print('Rewards Claimed after recovered funds: ', rr)
        # assert reward_token.balanceOf(owner) - balance-(r0[0])<3  # noqa
        # assert isclose(r0[1], reward_token_1.balanceOf(owner) - balance_usds,rel_tol=1e-18) # noqa
        total_rewards += rr[0]
    # Withdraw the deposit without initiating cooldown
    print('\n ----Withdrawing the deposit without cooldown---- ')
    if (farm_name == 'test_farm_with_lockup'):
        with brownie.reverts('Please initiate cooldown'):
            txn = farm.withdraw(  # noqa
                0,
                {'from': owner, 'gas_limit': GAS_LIMIT}
            )

    # Try to initiate a cooldown for wrong deposit
    with brownie.reverts('Deposit does not exist'):
        txn = farm.initiateCooldown(  # noqa
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Move ahead in time.
    chain.mine(10, chain.time() + 1000)
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

        if (farm_name == 'test_farm_with_lockup'):
            total_rewards += r1[0]+r1[2]
            # assert isclose(reward_token.balanceOf(owner),
            #                balance + r1[0] + r1[2], rel_tol=0.001)
        else:
            total_rewards += r1[0]
            assert isclose(reward_token.balanceOf(owner),
                           balance + r1[0], rel_tol=0.001)
    # Try to initiate a cooldown for a deposit already in cooldown
    with brownie.reverts('Can not initiate cooldown'):
        txn = farm.initiateCooldown(  # noqa
            0,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )

    # Withdraw during the cooldown period
    if (farm_name == 'test_farm_with_lockup'):
        print('\n ----Withdrawing the deposit without cooldown---- ')
        with brownie.reverts('Deposit is in cooldown'):
            txn = farm.withdraw(  # noqa
                0,
                {'from': owner, 'gas_limit': GAS_LIMIT}
            )

    # Try to withdraw for wrong deposit
    with brownie.reverts('Deposit does not exist'):
        txn = farm.withdraw(  # noqa
            1,
            {'from': owner, 'gas_limit': GAS_LIMIT}
        )
    tx = farm.getRewardBalance(usds, {'from': owner})
    tx = farm.getRewardBalance(spa, {'from': owner})
    # Move ahead in time.
    chain.mine(10, farm.deposits(owner, 0)[4])

    # Withdraw the deposit
    print('\n ----Withdrawing the deposit---- ')
    withdraw_txn = farm.withdraw(0, {'from': owner, 'gas_limit': GAS_LIMIT})
    print_stats(farm, token_id1)
    r2 = withdraw_txn.events['RewardsClaimed']['rewardAmount']
    print('Rewards Claimed: ', r2)
    total_rewards += r2[0]
    assert total_rewards == \
        withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][0]
    # assert withdraw_txn.events['DepositWithdrawn']['totalRewardsClaimed'][1] == r2[1]    # noqa

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
