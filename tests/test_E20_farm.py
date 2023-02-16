import math
from conftest import (
    GAS_LIMIT,
    OWNER,
    init_farm_e20,
    token_obj,
    fund_account,
    e20_constants,
    test_constants,
    mint_position,
    deploy_uni_farm,
    check_function,
    deployer_constants,
    funds,

)
# from conftest import (
#     create_deployer_farm_e20  # noqa
#       )

from brownie import (
    FarmFactory,
    Contract,
    accounts,
    Demeter_UniV2FarmDeployer,
    reverts,
    Demeter_E20_farm,
    chain,
    interface,
    ZERO_ADDRESS
)
from random import randint
import pytest
mint_position,
deploy_uni_farm,


# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']
deployers = ['CamelotFarmDeployer_v1']


@pytest.fixture(scope='module', autouse=True)
def setUp(config):
    global deployer, not_rwd_tkn, reward_tkn, lock_data, admin
    global no_lock_data, manager
    mint_position,
    deploy_uni_farm,
    deployer = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
    admin = accounts[0]
    not_rwd_tkn = token_obj('frax')
    no_lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000000')
    lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000001')
    manager = '0x6d5240f086637fb408c7F727010A10cf57D51B62'


@pytest.fixture(scope='module', autouse=True, params=farm_names)
def config(request):
    global farm_name
    farm_name = request.param
    farm_config = e20_constants()[farm_name]
    config = farm_config['config']
    # usd = interface.IUSDs("0xD74f5255D557944cf7Dd0E45FF521520002D5748")
    # usd.pauseSwitch(False, {'from': USDs_Owner})
    # print("USDs Transfers UnPaused")
    return config


@pytest.fixture(scope='module', autouse=True)
def test_config(request):
    test_config = test_constants()
    return test_config


@pytest.fixture(scope='module', autouse=True, params=deployers)
def deployer_config(request):
    deployers = request.param
    dep_config = deployer_constants()[deployers]
    return dep_config


@pytest.fixture(scope='module', autouse=True)
def factory(setUp):
    proxy = '0xC4fb09E0CD212367642974F6bA81D8e23780A659'

    factory_contract = Contract.from_abi(
        'FarmFactory',
        proxy,
        FarmFactory.abi
    )

    print('factory owner is:', factory_contract.owner())

    return factory_contract


@pytest.fixture(scope='module', autouse=True)
def farm_deployer(deployer_config, factory):
    """Deploying Uniswap Farm Proxy Contract"""
    print('Deploy Demeter_UniV2FarmDeployer contract.')
    print(list(deployer_config.values()))
    farm_f = deployer_config['farm_factory']
    protocol = deployer_config['protocol_factory']
    name = deployer_config['deployer_name']

    farm_deployer = Demeter_UniV2FarmDeployer.deploy(
        farm_f,
        protocol,
        name,
        {'from': deployer}
    )

    print('Register the deployer contract with the Factory.')
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )
    print('Farm Deployer Address is: ', farm_deployer)
    return farm_deployer


@pytest.fixture(scope='module', autouse=True)
def farm_contract(config):

    return deploy_uni_farm(deployer, Demeter_E20_farm)


@pytest.fixture(scope='module')
def farm(config, farm_contract):
    return init_farm_e20(deployer, farm_contract, config)

# NOTE: This deploys the farm from farm Deployer
# @pytest.fixture(scope='module', autouse=True)
# def farm(config, farm_deployer, factory):
#     print(farm_deployer, "Farm Deployer")
#     farm_contract = create_deployer_farm_e20(
#         deployer, farm_deployer, config, factory)
#     return farm_contract


@pytest.fixture(scope='module', autouse=True)
def funding_accounts(test_config):
    token = list(test_config['funding_data'].keys())
    amount = list(test_config['funding_data'].values())
    print('balances before funding')
    for _, tkn in enumerate(token):
        print('balance of ', token_obj(tkn).name(
        ), ' is', (token_obj(tkn).balanceOf(deployer) /
                   (10**token_obj(tkn).decimals())))
    for i, tkn in enumerate(token):
        fund_account(deployer, tkn, amount[i])
    # fund_account(accounts[i], token[i], amount[i]) #for multi user funding
        print(tkn, 'is funded ', amount[i] /
              (math.pow(10, token_obj(tkn).decimals())))
    print(token, amount)
    return token, amount


@ pytest.fixture(scope='module', autouse=True)
def reward_token(config):
    reward_tkn = list()
    reward_tkn.append(token_obj('spa'))  # Default reward token
    for i in range(len(config['reward_token_data'])):
        reward_tkn.append(interface.ERC20(
            config['reward_token_data'][i]['reward_tkn']))
    for _, tkn in enumerate(reward_tkn):
        rwd_token_name = tkn.name()
        print('reward token name is: ', rwd_token_name)
    return reward_tkn


def add_rewards(farm, reward_token, funding_accounts):
    farm_rewards = list()
    key, amount = funding_accounts
    for i, tkn in enumerate(reward_token):
        token_obj(key[i]).approve(farm, 2*amount[i], {'from': deployer})
        farm_rewards.append(farm.addRewards(
            tkn, 10000*10**tkn.decimals(),
            {'from': deployer}))
    return farm_rewards


def set_rewards_rate(farm, reward_token):
    rewards_rate = list()
    if (farm.cooldownPeriod() != 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            rwd_amt_lock = 2*rwd_amt_no_lock
            tx = farm.setRewardRate(tkn,
                                    [rwd_amt_no_lock,
                                     rwd_amt_lock],
                                    {'from': manager})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_amt_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_amt_lock
        print('rewards rate changed and checked!!')
        return rewards_rate
    if (farm.cooldownPeriod() == 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            tx = farm.setRewardRate(tkn,
                                    [rwd_amt_no_lock],
                                    {'from': manager})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_amt_no_lock
        print('rewards rate changed and checked!!')
        return rewards_rate


def set_invalid_rewards_rate_length(farm, reward_token):

    if (farm.cooldownPeriod() != 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            farm.setRewardRate(tkn,
                               [rwd_amt_no_lock],
                               {'from': manager})
        return print('invalid lockup rewards rate length passed!')
    if (farm.cooldownPeriod() == 0):
        for _, tkn in enumerate(reward_token):
            rwd_amt_no_lock = 1e-3*10**tkn.decimals()
            rwd_amt_lock = 2*rwd_amt_no_lock
            farm.setRewardRate(tkn,
                               [rwd_amt_no_lock, rwd_amt_lock],
                               {'from': manager})
        return print('invalid non-lockup rewards rate length passed!')


def create_deposit(farm, test_config, is_locked):
    """
    This helper function deposits into farms
    """
    number_deposits = test_config['number_of_deposits']
    print('number of Deposits are ', number_deposits)
    global amount
    amt_list = list()
    deposit = list()
    lp_token = interface.ERC20(farm.farmToken())
    amount = lp_token.balanceOf(funds('Camelot-LP'))
    for i in range(number_deposits):

        print('===Transfering LP Token to user', i+1, '===')
        amt = randint(1, (amount/number_deposits))
        _ = lp_token.transfer(
            accounts[i],
            amt+100,
            {'from': funds('Camelot-LP')}
        )

        print('=====Approving======')
        _ = lp_token.approve(
            farm.address, lp_token.balanceOf(accounts[i]),
            {'from': accounts[i]})
        print('=====Depositing Into Farms======')
        deposit_txn = farm.deposit(
            amt, is_locked,
            {'from': accounts[i]})
        print(dict(deposit_txn.events))
        print('Checking Deposit Parameters')
        assert deposit_txn.events['Deposited']['account'] == accounts[i]
        assert deposit_txn.events['Deposited']['liquidity'] == amt
        assert deposit_txn.events['Deposited']['locked'] is is_locked
        print('Deposit checks passed ✅✅')

        amt_list.append(amt)
        deposit.append(deposit_txn)
    return deposit


def create_deposits(farm, test_config):
    """
    This helper function deposits into farms
    """
    if (farm.cooldownPeriod() != 0):
        print('lockup deposit')
        return create_deposit(farm, test_config, True)
    elif (farm.cooldownPeriod() == 0):
        print('no lockup deposit')
        return create_deposit(farm, test_config, False)


# @pytest.mark.skip()
class Test_initialization:

    def test_initialization_reward_already_added(
        self, farm_contract, config
    ):
        rewardData = [
            {
                'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': deployer,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': deployer,
            },
        ]
        with reverts('Reward token already added'):
            farm_contract.initialize(
                config['farm_start_time'],
                config['cooldown_period'],
                config['uniswap_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_farm_start_time(
        self, config, farm_contract
    ):
        with reverts('Invalid farm startTime'):
            farm_contract.initialize(
                chain.time() - 1,
                config['cooldown_period'],
                config['uniswap_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     config['reward_token_data'])),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_cooldown_period(
        self, farm_contract, config
    ):
        # Test the case with max cooldown
        with reverts('Invalid cooldown period'):
            farm_contract.initialize(
                config['farm_start_time'],
                10000,
                config['uniswap_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     config['reward_token_data'])),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_initialization_rewards_more_than_four(
        self, farm_contract, config
    ):
        rewardData = [
            {
                'reward_tkn':
                    '0xD74f5255D557944cf7Dd0E45FF521520002D5748',
                    'tkn_manager': deployer,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': deployer,
            },
            {
                'reward_tkn':
                    '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    'tkn_manager': deployer,
            },
            {
                'reward_tkn':
                    '0x5575552988A3A80504bBaeB1311674fCFd40aD4B',
                    'tkn_manager': deployer,
            },
            {
                'reward_tkn':
                    '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                    'tkn_manager': deployer,
            },
        ]
        with reverts('Invalid reward data'):
            farm_contract.initialize(
                config['farm_start_time'],
                config['cooldown_period'],
                config['uniswap_pool_data']['token_A'],
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_initialization(self, farm):

        assert farm.SPA() == '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'
        manager = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
        assert farm.SPA_TOKEN_MANAGER() == manager
        assert farm.COMMON_FUND_ID() == 0
        assert farm.LOCKUP_FUND_ID() == 1
        assert farm.MIN_COOLDOWN_PERIOD() == 1
        assert farm.MAX_NUM_REWARDS() == 4
        assert not farm.isPaused()
        assert not farm.isClosed()


# @pytest.mark.skip()
class Test_private_functions:

    def test_subcribe_reward_fund(self, farm):
        func_name = '_subscribeRewardFund'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid fund id'):
            farm._subscribeRewardFund(4, 1, 1, {'from': deployer})

    def test_unsubcribe_reward_fund(self, farm):
        func_name = '_unsubscribeRewardFund'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid fund id'):
            farm._unsubscribeRewardFund(4, admin, 1, {'from': admin})

    def test_get_acc_rewards(self, farm):
        func_name = '_getAccRewards'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        farm._getAccRewards(0, 0, chain.time())

    # def test_get_acc_rewards_supply(self, farm):
    #     func_name = '_getAccRewards'
    #     if not check_function(farm, func_name):
    #         pytest.skip(f'NOTE: Function {func_name} needs to be made public') # noqa
    #     assert False
    #     farm._getAccRewards(0, 0, chain.time())

# @pytest.mark.skip()


class Test_admin_function:
    @pytest.fixture()
    def setup_rewards(self, fn_isolation, farm,
                      test_config, reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)

        return tx

    # @pytest.mark.skip()
    class Test_update_Token_Manager:

        def test_invalid_token_manager(self, farm):
            with reverts('Not the token manager'):
                farm.updateTokenManager(farm.SPA(), accounts[5], {
                    'from': accounts[4]})

        def test_zero_address(self, farm):
            with reverts('Invalid address'):
                farm.updateTokenManager(
                    farm.SPA(), ZERO_ADDRESS, {'from': deployer})

    # @pytest.mark.skip()
    class Test_update_cooldown:

        def test_updateCooldownPeriod_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.updateCooldownPeriod(
                    1, {'from': accounts[1], 'gas_limit': GAS_LIMIT})

        def test_farm_with_no_cooldown(self, farm):
            if (farm_name == 'test_farm_without_lockup'):
                with reverts('Farm does not support lockup'):
                    farm.updateCooldownPeriod(
                        3, {'from': deployer, 'gas_limit': GAS_LIMIT})

        def test_incorrect_cooldown(self, farm):
            if (farm_name == 'test_farm_with_lockup'):
                with reverts('Invalid cooldown period'):
                    farm.updateCooldownPeriod(
                        farm.MIN_COOLDOWN_PERIOD() - 1,
                        {'from': deployer, 'gas_limit': GAS_LIMIT}
                    )

                with reverts('Invalid cooldown period'):
                    farm.updateCooldownPeriod(
                        farm.MAX_COOLDOWN_PERIOD() + 1,
                        {'from': deployer, 'gas_limit': GAS_LIMIT}
                    )

        def test_update_cooldown(
            self,
            fn_isolation,
            farm,
            config,
            test_config
        ):
            if (farm_name == 'test_farm_with_lockup'):
                old_cooldown = farm.cooldownPeriod()
                new_cooldown = 5

                # Create a deposit with initial cooldown period
                _ = create_deposit(
                    farm, test_config, True
                )
                tx = farm.updateCooldownPeriod(
                    5, {'from': deployer, 'gas_limit': GAS_LIMIT})

                event = tx.events['CooldownPeriodUpdated']
                assert event['newCooldownPeriod'] == new_cooldown
                assert event['oldCooldownPeriod'] == old_cooldown
                assert farm.cooldownPeriod() == new_cooldown

                _ = create_deposit(
                    farm, test_config, True
                )

                print('\nAsserting positions before and after cooldown update')
                deposits = farm.getNumDeposits(admin)
                d1 = farm.getDeposit(admin, (deposits - 2))
                d2 = farm.getDeposit(admin, (deposits - 1))

                assert d1.dict()['cooldownPeriod'] == old_cooldown
                assert d2.dict()['cooldownPeriod'] == new_cooldown

    # @pytest.mark.skip()
    class Test_update_farm_start_time:
        def test_updateFarmStartTime_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.updateFarmStartTime(
                    chain.time() + 2, {'from': accounts[2]})

        def test_updateFarmStartTime_for_started_farm(self, farm):
            chain.mine(1, farm.farmStartTime())
            with reverts('Farm already started'):
                farm.updateFarmStartTime(
                    chain.time()+2, {'from': deployer})

        def test_updateFarmStartTime_in_past(self, farm):
            with reverts('Time < now'):
                farm.updateFarmStartTime(
                    chain.time()-2, {'from': deployer})

        def test_updateFarmStartTime(self, farm):
            newTime = chain.time() + 100
            tx = farm.updateFarmStartTime(
                newTime, {'from': deployer})
            event = tx.events['FarmStartTimeUpdated']
            assert newTime == event['newStartTime']
            assert newTime == farm.farmStartTime()
            assert newTime == farm.lastFundUpdateTime()

    # @pytest.mark.skip()
    class Test_farm_pause_switch:

        def test_farmPauseSwitch_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.farmPauseSwitch(
                    True, {'from': accounts[2]})

        def test_farmPauseSwitch_try_false(self, farm):
            with reverts('Farm already in required state'):
                farm.farmPauseSwitch(
                    False, {'from': deployer})

        def test_farmPauseSwitch_pause(self, farm):
            tx = farm.farmPauseSwitch(
                True, {'from': deployer})
            event = tx.events['FarmPaused']
            assert event['paused']
            with reverts('Farm paused'):
                farm.initiateCooldown(2, {'from': accounts[2]})

        def test_farmPauseSwitch_unpause(self, farm):
            farm.farmPauseSwitch(
                True, {'from': deployer})
            tx = farm.farmPauseSwitch(
                False, {'from': deployer})
            event = tx.events['FarmPaused']
            assert not event['paused']

    def test_deposit_paused(self, farm, test_config):
        farm.farmPauseSwitch(True, {'from': deployer})
        with reverts('Farm paused'):
            create_deposits(farm, test_config)

    def test_claim_rewards_paused(self, farm, setup_rewards, reward_token):
        chain.mine(10, None, 1000)
        farm.farmPauseSwitch(True, {'from': deployer})
        chain.mine(10, None, 1000)
        print('claiming rewards for the first time after pausing the farm')
        for i in range(len(setup_rewards)):
            tx = farm.claimRewards(0, {'from': accounts[i]})
            for i in range(len(reward_token)):
                assert tx.events['RewardsClaimed']['rewardAmount'][i] != 0
        print('checked first claimed rewards !=  0')
        print('claiming rewards for the second time after pausing the farm')
        for i in range(len(setup_rewards)):
            tx2 = farm.claimRewards(0, {'from': accounts[i]})
            for i in range(len(reward_token)):
                assert tx2.events['RewardsClaimed']['rewardAmount'][i] == 0
        print('checked reward claimed for second time = 0')

    def test_withdraw_paused_lockup_farm(self, farm, setup_rewards):
        chain.mine(10, None, 1000)
        farm.farmPauseSwitch(True, {'from': deployer})
        chain.mine(10, None, 1000)
        tx = farm.withdraw(0, {'from': admin})
        if(farm.cooldownPeriod() > 0):
            assert len(tx.events['PoolUnsubscribed']) == 2

    def test_change_reward_rates_paused(self, farm, reward_token):
        rwd_rate_no_lock = 2e15
        rwd_rate_lock = 4e15

        if (farm_name == 'test_farm_with_lockup'):
            farm.farmPauseSwitch(True, {'from': deployer})
            tx = farm.setRewardRate(reward_token[0],
                                    [rwd_rate_no_lock, rwd_rate_lock],
                                    {'from': OWNER, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_rate_lock
            print('unpausing the farm')
            farm.farmPauseSwitch(False, {'from': deployer})
            chain.mine(10, None, 1000)

            tx = farm.getRewardRates(reward_token[0])

            assert tx[0] == rwd_rate_no_lock
            assert tx[1] == rwd_rate_lock

        elif (farm_name == 'test_farm_without_lockup'):
            farm.farmPauseSwitch(True, {'from': deployer})
            tx = farm.setRewardRate(reward_token[0], [rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock

            print('unpausing the farm')
            farm.farmPauseSwitch(False, {'from': deployer})
            chain.mine(10, None, 1000)
            tx = farm.getRewardRates(reward_token[0])
            assert tx[0] == rwd_rate_no_lock

    # @pytest.mark.skip()
    class Test_close_farm:
        def test_closeFarm_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.closeFarm({'from': accounts[3]})

        def test_deposit_closed(self, farm,  test_config):
            farm.closeFarm({'from': deployer})
            with reverts('Farm paused'):
                create_deposits(farm, test_config)

        def test_withdraw_closed_lockup_farm(self, farm, setup_rewards):
            if (farm.cooldownPeriod() != 0):
                chain.mine(10, None, 1000)
                farm.closeFarm({'from': deployer})
                chain.mine(10, None, 1000)
                _ = farm.withdraw(0, {'from': admin})

        def test_close_farm_stop_reward_accrual(self, farm, setup_rewards,
                                                reward_token):
            _ = farm.recoverRewardFunds(farm.SPA(), 0, {'from': deployer})
            _ = farm.recoverRewardFunds(farm.SPA(), 1, {'from': deployer})
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                assert tx != 0
            tx = farm.closeFarm({'from': deployer})
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                assert tx == 0

        def test_close_farm_recover_funds(self, farm, setup_rewards,
                                          reward_token):
            rewards_balance = list()
            rewards_rate = list()
            for i, token in enumerate(reward_token):
                tx = farm.getRewardBalance(token)
                ty = farm.getRewardRates(token)
                rewards_rate.append(ty)
                rewards_balance.append(tx)
            print('reward Balances are:', rewards_balance)

            tx = farm.closeFarm({'from': deployer})
            if (farm_name == 'test_farm_with_lockup'):
                for i, token in enumerate(reward_token):
                    assert tx.events['FundsRecovered'][i]['amount'] >= \
                        rewards_balance[i] - \
                        rewards_rate[i][0]-rewards_rate[i][1]
                    assert tx.events['FundsRecovered'][i]['account'] == manager
                    assert tx.events['FundsRecovered'][i]['rwdToken'] == token
                    assert tx.events['RewardRateUpdated'][i]['newRewardRate'] \
                        == [0, 0]
            if (farm_name == 'test_farm_without_lockup'):
                for i, token in enumerate(reward_token):
                    assert tx.events['FundsRecovered'][i]['amount'] >= \
                        rewards_balance[i] - rewards_rate[i][0]
                    assert tx.events['FundsRecovered'][i]['account'] == manager
                    assert tx.events['FundsRecovered'][i]['rwdToken'] == token
                    assert tx.events['RewardRateUpdated'][i]['newRewardRate'] \
                        == [0]

        def test_close_farm_claim_rewards(self, farm):
            farm.closeFarm({'from': deployer})
            with reverts('Farm closed'):
                farm.claimRewards(
                    accounts[2], 2, {'from': accounts[2]})

    # @pytest.mark.skip()
    class Test_recover_ERC20:
        def test_recoverERC20_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.recoverERC20(not_rwd_tkn, {'from': accounts[4]})

        def test_recoverERC20_reward_token(self, farm, reward_token):
            with reverts('Can\'t withdraw rewardToken'):
                farm.recoverERC20(reward_token[0], {'from': deployer})

        def test_recoverERC20_zero_balance(self, farm):
            with reverts('Can\'t withdraw 0 amount'):
                farm.recoverERC20(not_rwd_tkn, {'from': deployer})

        def test_recoverERC20(self, farm):
            balance = 100 * 1e18
            fund_account(farm, 'frax', balance)
            beforeRecovery = not_rwd_tkn.balanceOf(deployer)
            tx = farm.recoverERC20(not_rwd_tkn, {'from': deployer})
            afterRecovery = not_rwd_tkn.balanceOf(deployer)
            event = tx.events['RecoveredERC20']
            assert event['token'] == not_rwd_tkn
            assert event['amount'] == balance
            assert afterRecovery - beforeRecovery == balance

        def test_recover_farm_token(self, farm):
            farm_token = '0x495dabd6506563ce892b8285704bd28f9ddcae65'
            with reverts("Can't withdraw farm token"):
                farm.recoverERC20(farm_token, {'from': deployer})


# @pytest.mark.skip()
class Test_view_functions:
    # @pytest.mark.skip()
    class Test_compute_rewards:
        def get_rewards(self, msg, farm, deposit):
            print(f'\n{msg}')
            rewards = []
            chain.mine(10, None, 86400)
            _ = farm.computeRewards(admin, 0)
            _ = tx = farm.computeRewards(admin, 0)
            for i in range(len(deposit)):
                tx = farm.computeRewards(accounts[i], 0)
                rewards.append(tx)
                print('rewards calculated for deposit ',
                      i, 'are: ', rewards[i])
            return rewards

        def test_computeRewards_invalid_deposit(self, farm,
                                                test_config):
            deposit = create_deposits(farm, test_config)
            with reverts('Deposit does not exist'):
                farm.computeRewards(admin, len(deposit)+1)

        def test_after_farm_starts(self, fn_isolation, farm,
                                   funding_accounts,
                                   test_config,
                                   reward_token):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(farm, test_config)
            _ = self.get_rewards('Compute rwd after farm start', farm, deposit)

        def test_during_farm_pause(
            self,
            fn_isolation,
            farm,

            funding_accounts,
            test_config,
            reward_token
        ):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposits = create_deposits(farm, test_config)
            chain.mine(1, None, 86400)

            _ = farm.farmPauseSwitch(True, {'from': farm.owner()})
            assert farm.isPaused()
            initial_rwd = self.get_rewards(
                'Compute rwd after farm pause day1', farm, deposits
            )

            rwd_after_pause = self.get_rewards(
                'Compute rwd after farm paused day2', farm, deposits
            )

            assert initial_rwd == rwd_after_pause

            _ = farm.closeFarm({'from': farm.owner()})
            assert farm.isClosed()

            rwd_after_close = self.get_rewards(
                'Compute rwd after farm closed', farm, deposits
            )
            assert initial_rwd == rwd_after_close

    def test_getNumDeposits(self, farm,  test_config):

        _ = create_deposits(farm, test_config)
        assert farm.getNumDeposits(admin) == 1

    def test_getNumSubscriptions(self, farm, test_config):
        deposits = create_deposits(farm, test_config)
        for i in range(len(deposits)):
            tx = farm.getNumSubscriptions(
                deposits[i].events['Deposited']['tokenId'])
            print('Token ID subscriptions are: ', tx)

    # @pytest.mark.skip()
    class Test_get_subscription_info:
        def test_getSubscriptionInfo_invalid_subscription(self, farm,
                                                          test_config):
            id_minted = create_deposits(farm, test_config)
            with reverts('Subscription does not exist'):
                farm.getSubscriptionInfo(
                    id_minted[0].events['Deposited']['tokenId'], 3)

        def test_getSubscriptionInfo(self, farm,
                                     test_config):
            tx = create_deposits(farm, test_config)
            _ = farm.getSubscriptionInfo(
                tx[0].events['Deposited']['tokenId'], 0)

    def test_invalid_reward_rates_length(self, farm, reward_token):
        if (farm_name == 'test_farm_with_lockup'):
            with reverts('Invalid reward rates length'):
                farm.setRewardRate(reward_token[0], [1000], {
                                   'from': OWNER, 'gas_limit': GAS_LIMIT})
        elif (farm_name == 'test_farm_without_lockup'):
            with reverts('Invalid reward rates length'):
                farm.setRewardRate(reward_token[0], [1000, 2000], {
                                   'from': OWNER, 'gas_limit': GAS_LIMIT})

    def test_reward_rates_data(self, farm, reward_token):
        rwd_rate_no_lock = 1e15
        rwd_rate_lock = 2e15

        if (farm_name == 'test_farm_with_lockup'):
            tx = farm.setRewardRate(reward_token[0],
                                    [rwd_rate_no_lock, rwd_rate_lock],
                                    {'from': OWNER, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                rwd_rate_lock
        elif (farm_name == 'test_farm_without_lockup'):
            tx = farm.setRewardRate(reward_token[0], [rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_rate_no_lock
        print('changing reward rates for the second time........ ')
        new_rwd_rate_no_lock = 15e14
        new_rwd_rate_lock = 3e15
        if (farm_name == 'test_farm_with_lockup'):
            tx = farm.setRewardRate(reward_token[0],
                                    [new_rwd_rate_no_lock, new_rwd_rate_lock],
                                    {'from': OWNER, 'gas_limit': GAS_LIMIT})

            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['oldRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['oldRewardRate'][1] == \
                rwd_rate_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                new_rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] == \
                new_rwd_rate_lock
        elif (farm_name == 'test_farm_without_lockup'):

            tx = farm.setRewardRate(reward_token[0], [new_rwd_rate_no_lock], {
                'from': OWNER, 'gas_limit': GAS_LIMIT})
            assert tx.events['RewardRateUpdated']['rwdToken'] == \
                reward_token[0]
            assert tx.events['RewardRateUpdated']['oldRewardRate'][0] == \
                rwd_rate_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                new_rwd_rate_no_lock

    # @pytest.mark.skip()
    class Test_get_reward_fund_info:
        def test_getRewardFundInfo_more_than_added(self, farm):
            with reverts('Reward fund does not exist'):
                farm.getRewardFundInfo(3)

        def test_getRewardFundInfo(self, farm, funding_accounts, reward_token,
                                   test_config):
            total_liquidity = 0
            _ = add_rewards(farm, reward_token, funding_accounts)
            rate = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(farm, test_config)
            fund_id = 0
            if(farm_name == 'test_farm_with_lockup'):
                fund_id = 1
            res = farm.getRewardFundInfo(fund_id)

            for rwd, _ in enumerate(reward_token):
                assert res[1][rwd] == \
                    rate[rwd].events[
                        'RewardRateUpdated'
                ]['newRewardRate'][fund_id]
            for _, dep in enumerate(deposit):
                total_liquidity += dep.events['Deposited']['liquidity']
            assert res[0] == total_liquidity

    # @pytest.mark.skip()
    class Test_get_reward_balance:
        @pytest.fixture()
        def setup(self, fn_isolation, farm,
                  test_config,

                  reward_token, funding_accounts):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            tx = create_deposits(farm, test_config)
            chain.mine(10, None, 86400)
            return tx

        def test_getRewardBalance_invalid_rwdToken(self, farm):
            with reverts('Invalid _rwdToken'):
                farm.getRewardBalance(not_rwd_tkn, {'from': admin})

        def test_getRewardBalance_rewardsAcc_more_than_supply(self,
                                                              reward_token,
                                                              farm, setup):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': admin})
                print(tx, 'is reward balance')

        def test_getRewardBalance(self, farm, setup, reward_token):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': admin})
                print(tx, 'is reward balance')


# @pytest.mark.skip()
class Test_recover_reward_funds:
    @pytest.fixture()
    def setup(self, fn_isolation, farm,
              test_config,
              reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)
        return tx

    def test_recover_reward_funds(self, reward_token, setup, farm):
        recovered_funds = list()
        for i, tkn in enumerate(reward_token):
            tx = farm.recoverRewardFunds(tkn, farm.getRewardBalance(
                tkn, {'from': OWNER}), {'from': OWNER})
            recovered_funds.append(tx)
            assert recovered_funds[i].events['FundsRecovered']['rwdToken'] == \
                tkn
            assert recovered_funds[i].events['FundsRecovered']['amount'] != 0
            assert recovered_funds[i].events['FundsRecovered']['account'] == \
                OWNER
            # Reward Accrual Stopped
            assert farm.getRewardBalance(tkn, {'from': OWNER}) == 0

    def test_recover_reward_funds_uint256_max(self, reward_token, setup, farm):
        UINT256_MAX = \
            115792089237316195423570985008687907853269984665640564039457584007913129639935  # noqa
        for token in reward_token:
            init_bal = farm.getRewardBalance(token)
            tx = farm.recoverRewardFunds(token, UINT256_MAX, {'from': OWNER})
            ev = tx.events['FundsRecovered']
            assert ev['amount'] <= init_bal


# @pytest.mark.skip()
class Test_set_reward_rate:

    def test_set_reward_rate(self, farm, reward_token):
        set_rewards_rate(farm, reward_token)

    def test_set_invalid_reward_rate_length(self, farm, reward_token):
        set_rewards_rate(farm, reward_token)


# @pytest.mark.skip()
class Test_add_rewards:
    def test_invalid_reward(self, farm):
        with reverts('Invalid reward token'):
            farm.addRewards(ZERO_ADDRESS, 10e2, {'from': admin})

    def test_add_rewards(self, fn_isolation, farm,
                         reward_token,
                         funding_accounts):
        tx = add_rewards(farm, reward_token, funding_accounts)

        for i, tkn in enumerate(reward_token):
            assert tkn.address == \
                tx[i].events['RewardAdded']['rwdToken']
            assert tx[i].events['RewardAdded']['amount'] == 10000 * \
                10**tkn.decimals()
            print('Reward token', tkn.name(), 'is checked!!')
            assert tx[i].events['Transfer']['from'] == deployer
            print('checked the spender for the reward token',
                  tkn.name())


# @pytest.mark.skip()
class Test_deposit:

    def test_increase_deposit_cooldown(self, farm,  test_config):
        if (farm.cooldownPeriod() != 0):
            _ = create_deposit(farm, test_config, True)
            chain.mine(10, None, 86400)
            farm.initiateCooldown(
                0,
                {'from': admin}
            )
            with reverts('Deposit in cooldown'):
                _ = farm.increaseDeposit(0, 1, {'from': accounts[0]})

    def test_increase_deposit_0_amount(self, farm,  test_config):
        _ = create_deposit(farm, test_config, False)
        with reverts('Invalid amount'):
            _ = farm.increaseDeposit(0, 0, {'from': accounts[0]})

    def test_increase_deposit(self, farm,  test_config):
        tx = create_deposit(farm, test_config, False)
        for i in range(len(tx)):
            _ = farm.increaseDeposit(0, 1, {'from': accounts[i]})

    def test_lockup_disabled(self, farm,  test_config):
        if (farm.cooldownPeriod() == 0):
            with reverts('Lockup functionality is disabled'):
                create_deposit(farm, test_config, True)

    def test_successful_deposit_with_lockup(self, farm,

                                            test_config):
        _ = create_deposits(farm, test_config)

    def test_successful_deposit_without_lockup(self, farm,

                                               test_config):

        _ = create_deposits(farm, test_config)


# @pytest.mark.skip()
class Test_claim_rewards:
    @pytest.fixture()
    def setup(self, fn_isolation, farm,  test_config,
              reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)

        return tx

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.claimRewards(
                len(setup)+1,
                {'from': deployer}
            )

    def test_claim_rewards_for_self(self, farm, setup):
        claimed_tx = list()
        if (farm_name == 'test_farm_with_lockup'):
            for i, txn in enumerate(setup):
                tx = farm.claimRewards(0, {'from': accounts[i]})
                claimed_tx.append(tx)
                assert len(tx.events['RewardsClaimed']) == 2
                assert txn.events['Deposited']['tokenId'] == \
                    claimed_tx[i].events['RewardsClaimed']['tokenId']
                assert txn.events['Deposited']['account'] == \
                    claimed_tx[i].events['RewardsClaimed']['account']
                assert txn.events['Deposited']['liquidity'] == \
                    claimed_tx[i].events['RewardsClaimed']['liquidity']
            print('claiming rewards check passed!')
        elif (farm_name == 'test_farm_without_lockup'):
            for i, txn in enumerate(setup):
                tx = farm.claimRewards(0, {'from': accounts[i]})
                claimed_tx.append(tx)
                assert len(tx.events['RewardsClaimed']) == 1
                assert txn.events['Deposited']['tokenId'] == \
                    claimed_tx[i].events['RewardsClaimed']['tokenId']
                assert txn.events['Deposited']['account'] == \
                    claimed_tx[i].events['RewardsClaimed']['account']
                assert txn.events['Deposited']['liquidity'] == \
                    claimed_tx[i].events['RewardsClaimed']['liquidity']
            print('claiming rewards check passed!')

    def test_claim_rewards_for_other_address(self, farm, setup):
        with reverts('Deposit does not exist'):
            _ = farm.claimRewards(0, {'from': accounts[2]})

    def test_multiple_reward_claims(self, farm, setup):
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': accounts[i]})
            # for i, tx in enumerate(setup):

        chain.mine(10, None, 86400)
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': accounts[i]})

        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': accounts[i]})
        for i in range(len(setup)):
            _ = farm.claimRewards(0, {'from': accounts[i]})

    def test_claiming_without_rewards(self, farm,
                                      test_config):
        tx = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)
        for i in range(len(tx)):
            tx = farm.claimRewards(0, {'from': accounts[i]})


# @pytest.mark.skip()
class Test_initiate_cooldown:
    @ pytest.fixture(scope='function')
    def setup(self, farm,  test_config,
              reward_token, funding_accounts, fn_isolation):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            _ = farm.claimRewards(0, {'from': accounts[i]})

        return deposit

    def test_no_lockup(self, farm, setup):
        if (farm.cooldownPeriod() == 0):
            with reverts('Can not initiate cooldown'):
                farm.initiateCooldown(
                    0,
                    {'from': admin}
                )

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.initiateCooldown(
                len(setup)+1,
                {'from': deployer}
            )

    def test_for_unlocked_deposit(self, farm, setup):

        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': admin}
            )

    def test_initiate_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': admin}
            )


# @pytest.mark.skip()
class Test_withdraw:
    @pytest.fixture(scope='function')
    def setup(self, farm,  test_config,
              reward_token, funding_accounts, fn_isolation):
        claimed = list()
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, test_config)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            claimed.append(farm.claimRewards(0, {'from': accounts[i]}))

        return deposit, claimed

    def test_withdraw_partially_lockup_cooldown(self, farm,  test_config):
        if (farm.cooldownPeriod() != 0):
            _ = create_deposit(farm, test_config, True)
            farm.initiateCooldown(
                0,
                {'from': admin}
            )
            with reverts('Partial withdraw not permitted'):
                farm.withdrawPartially(
                    0,
                    1,
                    {'from': admin}
                )

    def test_partially_invalid_amount(self, farm, setup):
        with reverts('Invalid amount'):
            farm.withdrawPartially(
                0,
                0,
                {'from': admin}
            )

    def test_partially_invalid_amount_bigger(self, farm, setup):
        with reverts('Invalid amount'):
            farm.withdrawPartially(
                0,
                1e35,
                {'from': admin}
            )

    def test_partially_invalid_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            with reverts('Partial withdraw not permitted'):
                farm.withdrawPartially(
                    0,
                    1,
                    {'from': admin}
                )

    def test_partially(self, farm, setup):
        if (farm.cooldownPeriod() == 0):
            farm.withdrawPartially(
                0,
                100,
                {'from': admin}
            )

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.withdraw(
                len(setup) + 1,
                {'from': admin}
            )

    def test_farm_paused(self, farm, setup):
        withdraw_txns = list()
        farm.farmPauseSwitch(True, {'from': deployer})
        for i in range(len(setup)):
            withdraw_txns.append(farm.withdraw(0, {'from': accounts[i]}))

    def test_cooldown_not_initiated(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            with reverts('Please initiate cooldown'):
                for i in range(len(setup)):
                    farm.withdraw(0, {'from': accounts[i]})

    def test_deposit_in_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': admin}
            )
            with reverts('Deposit is in cooldown'):
                farm.withdraw(
                    0,
                    {'from': admin}
                )

    def test_withdraw(self, setup, farm):
        withdraws = list()
        if (farm.cooldownPeriod() != 0):
            for i in range(len(setup)):
                farm.initiateCooldown(
                    0,
                    {'from': accounts[i]}
                )
                chain.mine(10, farm.deposits(
                    accounts[i], 0)['expiryDate'] + 10)
                farm.computeRewards(accounts[i], 0, {'from': accounts[i]})
                farm.computeRewards(accounts[i], 0, {'from': accounts[i]})
                withdraws.append(farm.withdraw(0, {'from': accounts[i]}))

            farm.getRewardBalance(farm.SPA(), {'from': admin})
        if (farm.cooldownPeriod() == 0):
            for i in range(len(setup)):
                farm.computeRewards(accounts[i], 0,)

                withdraws.append(farm.withdraw(0, {'from': accounts[i]}))

            farm.getRewardBalance(farm.SPA(), {'from': admin})
