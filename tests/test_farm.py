from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    Demeter_UniswapV3FarmDeployer_v2,
    ProxyAdmin,
    reverts,
    UniswapV3Test,
    Demeter_UniV3Farm_v2,
    chain,
    interface,
    ZERO_ADDRESS
)
from random import randint
import pytest
import eth_utils
from conftest import (
    GAS_LIMIT,
    OWNER,
    mint_position,
    deploy_uni_farm,
    token_obj,
    fund_account,
    constants,
    test_constants,
    check_function,
    create_deployer_farm

)

# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']


@pytest.fixture(scope='module', autouse=True)
def setUp(config):
    global deployer, not_rwd_tkn, reward_tkn, lock_data
    global no_lock_data, manager
    deployer = accounts[0]
    not_rwd_tkn = token_obj('frax')
    no_lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000000')
    lock_data = (
        '0x0000000000000000000000000000000000000000000000000000000000000001')
    manager = '0x6d5240f086637fb408c7F727010A10cf57D51B62'


@pytest.fixture(scope='module', autouse=True)
def uniswap_simulator():
    uniswap_sim = UniswapV3Test.deploy({'from': deployer})
    return uniswap_sim


@pytest.fixture(scope='module', autouse=True, params=farm_names)
def config(request):
    global farm_name
    farm_name = request.param
    farm_config = constants()[farm_name]
    config = farm_config['config']
    return config


@pytest.fixture(scope='module', autouse=True)
def test_config(request):
    test_config = test_constants()
    return test_config


@pytest.fixture(scope='module', autouse=True)
def factory(setUp):
    factory_impl = FarmFactory.deploy(
        {'from': deployer}
    )
    print('Deploy Proxy Admin.')
    # Deploy the proxy admin contract
    proxy_admin = ProxyAdmin.deploy(
        {'from': deployer, 'gas': GAS_LIMIT})
    proxy = TransparentUpgradeableProxy.deploy(
        factory_impl.address,
        proxy_admin.address,
        eth_utils.to_bytes(hexstr='0x'),
        {'from': deployer, 'gas_limit': GAS_LIMIT},
    )

    factory_contract = Contract.from_abi(
        'FarmFactory',
        proxy.address,
        FarmFactory.abi
    )

    factory_contract.initialize(
        deployer,
        token_obj('usds'),
        500e18,
        {'from': deployer}
    )
    print('factory owner is:', factory_contract.owner())
    return factory_contract


@pytest.fixture(scope='module', autouse=True)
def farm_deployer(factory):
    """Deploying Uniswap Farm Proxy Contract"""
    print('Deploy Demeter_UniswapV3FarmDeployer_v2 contract.')
    farm_deployer = Demeter_UniswapV3FarmDeployer_v2.deploy(
        factory,
        {'from': deployer}
    )

    print('Register the deployer contract with the Factory.')
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )
    return farm_deployer


@pytest.fixture(scope='module', autouse=True)
def farm_contract(config):
    return deploy_uni_farm(deployer, Demeter_UniV3Farm_v2)


# @pytest.fixture(scope='module')
# def farm(config, farm_contract):
#     return init_farm(deployer, farm_contract, config)

@pytest.fixture(scope='module')
def farm(config, farm_deployer):
    tx = create_deployer_farm(deployer, farm_deployer, config)
    return tx


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
              (10**token_obj(tkn).decimals()))
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


def simulate_swap(config, farm, uniswap_simulator, amtIn):
    token_a_obj = interface.ERC20(config['uniswap_pool_data']['token_A'])
    token_b_obj = interface.ERC20(config['uniswap_pool_data']['token_B'])
    token_a_decimals = token_a_obj.decimals()
    token_a_obj.transfer(
        uniswap_simulator,
        amtIn * 10 ** token_a_decimals,
        {'from': deployer}
    )

    _ = uniswap_simulator.swap(
        token_a_obj,
        token_b_obj,
        config['uniswap_pool_data']['fee_tier'],
        amtIn * 10 ** token_a_decimals
    )


def mint_pos(config, pm):
    token_a_obj = interface.ERC20(config['uniswap_pool_data']['token_A'])
    token_b_obj = interface.ERC20(config['uniswap_pool_data']['token_B'])
    token_a_decimals = token_a_obj.decimals()
    token_b_decimals = token_b_obj.decimals()

    amt_a = randint(100, 1000) * 10 ** token_a_decimals
    amt_b = randint(100, 1000) * 10 ** token_b_decimals
    pos = mint_position(
        pm,
        token_a_obj,
        token_b_obj,
        config['uniswap_pool_data']['fee_tier'],
        config['uniswap_pool_data']['lower_tick'],
        config['uniswap_pool_data']['upper_tick'],
        amt_a,
        amt_b,
        deployer,
    )
    return pos, amt_a, amt_b


@pytest.fixture(scope='module', autouse=True)
def minted_positions(config, test_config, pm):
    global amount_a, amount_b
    token_id = list()
    amount_a = list()
    amount_b = list()

    for i in range(test_config['number_of_deposits']):
        pos, amt_a, amt_b = mint_pos(config, pm)
        amount_a.append(amt_a)
        amount_a.append(amt_b)
        token_id.append(pos)
    print(token_id)
    return token_id


def create_deposit(farm, pm, token_id, data, is_locked):
    deposit_txn = pm.safeTransferFrom(
        deployer,
        farm.address,
        token_id,
        data,
        {'from': deployer},
    )
    assert deposit_txn.events['Deposited']['account'] == deployer
    assert deposit_txn.events['Deposited']['tokenId'] == token_id
    assert deposit_txn.events['Transfer']['to'] == farm.address
    assert deposit_txn.events['Deposited']['locked'] is is_locked
    print('Deposit checks passed ✅✅')
    return deposit_txn


def create_deposits(farm, minted_positions, pm):
    """
    This helper function deposits into farms
    """

    print('token Ids are: ', minted_positions)
    tx = list()
    if (farm.cooldownPeriod() != 0):
        print('lockup deposit')
        for i, token_id in enumerate(minted_positions):
            deposit_txn = create_deposit(
                farm,
                pm,
                token_id,
                lock_data,
                True
            )
            tx.append(deposit_txn)
        return tx
    elif (farm.cooldownPeriod() == 0):
        print('no lockup deposit')
        for i, token_id in enumerate(minted_positions):
            deposit_txn = create_deposit(
                farm,
                pm,
                token_id,
                no_lock_data,
                False
            )
            tx.append(deposit_txn)
        return tx


# @pytest.mark.skip()
class Test_initialization:

    def test_intitialization_false_pool_data(
        self, farm_contract, config, test_config
    ):
        with reverts('Invalid uniswap pool config'):
            farm_contract.initialize(
                chain.time() + 100,
                config['cooldown_period'],
                list(test_config['uniswap_pool_false_data'].values()),
                list(map(lambda x: list(x.values()),
                     config['reward_token_data'])),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_farm_start_time(
        self, config, farm_contract
    ):
        with reverts('Invalid farm startTime'):
            farm_contract.initialize(
                chain.time() - 1,
                config['cooldown_period'],
                list(config['uniswap_pool_data'].values()),
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
                list(config['uniswap_pool_data'].values()),
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
                list(config['uniswap_pool_data'].values()),
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

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
                list(config['uniswap_pool_data'].values()),
                list(map(lambda x: list(x.values()),
                     rewardData)),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_initialization(self, farm):

        assert farm.SPA() == '0x5575552988A3A80504bBaeB1311674fCFd40aD4B'
        manager = '0x6d5240f086637fb408c7F727010A10cf57D51B62'
        assert farm.SPA_TOKEN_MANAGER() == manager
        assert farm.NFPM() == '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
        factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984'
        assert farm.UNIV3_FACTORY() == factory
        assert farm.COMMON_FUND_ID() == 0
        assert farm.LOCKUP_FUND_ID() == 1
        assert farm.MIN_COOLDOWN_PERIOD() == 1
        assert farm.MAX_NUM_REWARDS() == 4
        assert not farm.isPaused()
        assert not farm.isClosed()


# @pytest.mark.skip()
class Test_admin_function:
    @pytest.fixture()
    def setup_rewards(self, fn_isolation, farm, minted_positions,
                      pm, reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, minted_positions, pm)
        chain.mine(10, None, 86400)

        return tx

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
            pm
        ):
            if (farm_name == 'test_farm_with_lockup'):
                old_cooldown = farm.cooldownPeriod()
                new_cooldown = 5

                # Create a deposit with initial cooldown period
                pos1, _, _ = mint_pos(config, pm)
                _ = create_deposit(
                    farm, pm, pos1, lock_data, True
                )
                tx = farm.updateCooldownPeriod(
                    5, {'from': deployer, 'gas_limit': GAS_LIMIT})

                event = tx.events['CooldownPeriodUpdated']
                assert event['newCooldownPeriod'] == new_cooldown
                assert event['oldCooldownPeriod'] == old_cooldown
                assert farm.cooldownPeriod() == new_cooldown

                pos2, _, _ = mint_pos(config, pm)
                _ = create_deposit(
                    farm, pm, pos2, lock_data, True
                )

                print('\nAsserting positions before and after cooldown update')
                n = farm.getNumDeposits(deployer)
                d1 = farm.getDeposit(deployer, n - 2)
                d2 = farm.getDeposit(deployer, n - 1)

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

    def test_deposit_paused(self, farm, minted_positions, pm):
        farm.farmPauseSwitch(True, {'from': deployer})
        with reverts('Farm paused'):
            create_deposits(farm, minted_positions, pm)

    def test_claim_rewards_paused(self, farm, setup_rewards, reward_token):
        chain.mine(10, None, 1000)
        farm.farmPauseSwitch(True, {'from': deployer})
        chain.mine(10, None, 1000)
        print('claiming rewards for the first time after pausing the farm')
        for i in range(len(setup_rewards)):
            tx = farm.claimRewards(i, {'from': deployer})
            for i in range(len(reward_token)):
                assert tx.events['RewardsClaimed']['rewardAmount'][i] != 0
        print('checked first claimed rewards !=  0')
        print('claiming rewards for the second time after pausing the farm')
        for i in range(len(setup_rewards)):
            tx2 = farm.claimRewards(i, {'from': deployer})
            for i in range(len(reward_token)):
                assert tx2.events['RewardsClaimed']['rewardAmount'][i] == 0
        print('checked reward claimed for second time = 0')

    def test_withdraw_paused_lockup_farm(self, farm, setup_rewards):
        if (farm.cooldownPeriod() != 0):
            chain.mine(10, None, 1000)
            farm.farmPauseSwitch(True, {'from': deployer})
            chain.mine(10, None, 1000)
            _ = farm.withdraw(0, {'from': deployer})

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

        def test_deposit_closed(self, farm, minted_positions, pm):
            farm.closeFarm({'from': deployer})
            with reverts('Farm paused'):
                create_deposits(farm, minted_positions, pm)

        def test_withdraw_closed_lockup_farm(self, farm, setup_rewards):
            if (farm.cooldownPeriod() != 0):
                chain.mine(10, None, 1000)
                farm.closeFarm({'from': deployer})
                chain.mine(10, None, 1000)
                _ = farm.withdraw(0, {'from': deployer})

        def test_close_farm_stop_reward_accrual(self, farm, setup_rewards,
                                                reward_token):
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


# @pytest.mark.skip()
class Test_view_functions:
    # @pytest.mark.skip()
    class Test_compute_rewards:
        def get_rewards(self, msg, farm, deposit):
            print(f'\n{msg}')
            rewards = []
            chain.mine(10, None, 86400)
            for i in range(len(deposit)):
                tx = farm.computeRewards(deployer, i)
                rewards.append(tx)
                print('rewards calculated for deposit ',
                      i, 'are: ', rewards[i])
            return rewards

        def test_computeRewards_invalid_deposit(self, farm, minted_positions,
                                                pm):
            deposit = create_deposits(farm, minted_positions, pm)
            with reverts('Deposit does not exist'):
                farm.computeRewards(deployer, len(deposit)+1)

        def test_after_farm_starts(self, fn_isolation, farm, minted_positions,
                                   funding_accounts,
                                   pm,
                                   reward_token):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(farm, minted_positions, pm)
            _ = self.get_rewards('Compute rwd after farm start', farm, deposit)

        def test_during_farm_pause(
            self,
            fn_isolation,
            farm,
            minted_positions,
            funding_accounts,
            pm,
            reward_token
        ):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            deposits = create_deposits(farm, minted_positions, pm)
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

    def test_getNumDeposits(self, farm, minted_positions, pm):

        deposit = create_deposits(farm, minted_positions, pm)
        assert farm.getNumDeposits(deployer) == len(deposit)

    def test_getLiquidity(self, farm, minted_positions, pm):
        func_name = '_getLiquidity'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        for i, token_id in enumerate(minted_positions):
            liquidity = farm._getLiquidity(token_id,
                                           {'from': deployer})
            assert liquidity == pm.positions(minted_positions[i])[7]
        print('get liquidity checks passed')

    def test_getLiquidity_incorrect_pool_tkn(self, farm):
        func_name = '_getLiquidity'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Incorrect pool token'):
            farm._getLiquidity(117684)

    def test_getLiquidity_incorrect_tick_range(self, farm, pm):
        func_name = '_getLiquidity'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Incorrect pool token'):
            farm._getLiquidity(117684)

    def test_getNumSubscriptions(self, farm, minted_positions,
                                 pm):
        for i, token_id in enumerate(minted_positions):
            tx = farm.getNumSubscriptions(token_id)
            print('Token ID subscriptions are: ', tx)

    @pytest.mark.parametrize('lower_tick, higer_tick',
                             [(-887220, -887220),
                              (-887273, 887210),
                              (-887219, 887210),
                              (-887220, 887273),
                              (-887220, 887219)])
    def test_invalid_uniswap_tick_ranges(self, farm, lower_tick, higer_tick):
        func_name = '_validateTickRange'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid tick range'):
            farm._validateTickRange(lower_tick, higer_tick)

    def test_zero_address(self, farm):
        func_name = '_validateTickRange'
        if not check_function(farm, func_name):
            pytest.skip(f'NOTE: Function {func_name} needs to be made public')
        with reverts('Invalid address'):
            farm._isNonZeroAddr(ZERO_ADDRESS, {'from': deployer})

    # @pytest.mark.skip()
    class Test_get_subscription_info:
        def test_getSubscriptionInfo_invalid_subscription(self, farm,
                                                          minted_positions):
            id_minted = minted_positions
            with reverts('Subscription does not exist'):
                farm.getSubscriptionInfo(id_minted[0], 3)

        def test_getSubscriptionInfo(self, farm, minted_positions,
                                     pm):
            _ = create_deposits(farm, minted_positions, pm)
            _ = farm.getSubscriptionInfo(minted_positions[0], 0)

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
                                   minted_positions, pm):
            total_liquidity = 0
            _ = add_rewards(farm, reward_token, funding_accounts)
            rate = set_rewards_rate(farm, reward_token)
            deposit = create_deposits(farm, minted_positions, pm)
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
        def setup(self, fn_isolation, farm, minted_positions,
                  pm,
                  reward_token, funding_accounts):
            _ = add_rewards(farm, reward_token, funding_accounts)
            _ = set_rewards_rate(farm, reward_token)
            tx = create_deposits(farm, minted_positions, pm)
            chain.mine(10, None, 86400)
            return tx

        def test_getRewardBalance_invalid_rwdToken(self, farm):
            with reverts('Invalid _rwdToken'):
                farm.getRewardBalance(not_rwd_tkn, {'from': deployer})

        def test_getRewardBalance_rewardsAcc_more_than_supply(self,
                                                              reward_token,
                                                              farm, setup):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': deployer})
                print(tx, 'is reward balance')

        def test_getRewardBalance(self, farm, setup, reward_token):
            for _, tkn in enumerate(reward_token):
                tx = farm.getRewardBalance(tkn, {'from': deployer})
                print(tx, 'is reward balance')


# @pytest.mark.skip()
class Test_recover_reward_funds:
    @pytest.fixture()
    def setup(self, fn_isolation, farm, minted_positions,
              pm,
              reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, minted_positions, pm)
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
            farm.addRewards(ZERO_ADDRESS, 10e2, {'from': deployer})

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

    def test_call_not_via_NFTM(self, farm, minted_positions):
        token_id = minted_positions
        with reverts('onERC721Received: not a univ3 nft'):
            farm.onERC721Received(
                accounts[2],
                deployer,
                token_id[0],
                no_lock_data,
                {'from': deployer},
            )

    def test_empty_data(self, farm, minted_positions, pm):
        token_id = minted_positions
        if (farm.cooldownPeriod() != 0):
            with reverts('onERC721Received: no data'):
                pm.safeTransferFrom(
                    deployer,
                    farm.address,
                    token_id[0],
                    {'from': deployer})

    def test_lockup_disabled(self, farm, minted_positions, pm):
        token_id = minted_positions
        print('token Ids are: ', token_id)
        if (farm.cooldownPeriod() == 0):
            with reverts('Lockup functionality is disabled'):
                farm.onERC721Received(
                    accounts[2],
                    deployer,
                    token_id[0],
                    lock_data,
                    {'from': pm.address},
                )

    def test_successful_deposit_with_lockup(self, farm,
                                            minted_positions,
                                            pm):
        _ = create_deposits(farm, minted_positions, pm)
        print('amount A', amount_a)
        print('amount B', amount_b)

    def test_successful_deposit_without_lockup(self, farm,
                                               minted_positions,
                                               pm):

        _ = create_deposits(farm, minted_positions, pm)
        print('amount A', amount_a)
        print('amount B', amount_b)


class Test_claim_uniswap_fee:
    @pytest.fixture()
    def setup(
        self,
        fn_isolation,
        config,
        uniswap_simulator,
        farm,
        minted_positions,
        pm,
        reward_token,
        funding_accounts
    ):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, minted_positions, pm)
        simulate_swap(config, farm, uniswap_simulator, 10000)
        chain.mine(10, None, 86400)
        return tx

    def test_calculate_fee(self, farm, setup):
        uniswap_fee = farm.computeUniswapFee(deployer, 0)
        print(f'Uniswap fee collected: {uniswap_fee}')
        assert uniswap_fee != (0, 0)

    def test_claim_uniswap_fee(self, farm, setup):
        uniswap_fee = farm.computeUniswapFee(deployer, 0)
        tx = farm.claimUniswapFee(0, {'from': deployer})
        claim_ev = tx.events['PoolFeeCollected']

        assert claim_ev['amt0Recv'] <= uniswap_fee[0]
        assert claim_ev['amt1Recv'] <= uniswap_fee[1]

        # Should claim all the fees for the user.
        with reverts('No fee to claim'):
            _ = farm.claimUniswapFee(0, {'from': deployer})


# @pytest.mark.skip()
class Test_claim_rewards:
    @pytest.fixture()
    def setup(self, fn_isolation, farm, minted_positions, pm,
              reward_token, funding_accounts):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        tx = create_deposits(farm, minted_positions, pm)
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
                tx = farm.claimRewards(i, {'from': deployer})
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
                tx = farm.claimRewards(i, {'from': deployer})
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
            _ = farm.claimRewards(i, {'from': deployer})
            # for i, tx in enumerate(setup):

        chain.mine(10, None, 86400)
        for i in range(len(setup)):
            _ = farm.claimRewards(i, {'from': deployer})

        for i in range(len(setup)):
            _ = farm.claimRewards(i, {'from': deployer})
        for i in range(len(setup)):
            _ = farm.claimRewards(i, {'from': deployer})

    def test_claiming_without_rewards(self, farm, minted_positions,
                                      pm):
        tx = create_deposits(farm, minted_positions, pm)
        chain.mine(10, None, 86400)
        for i in range(len(tx)):
            tx = farm.claimRewards(i, {'from': deployer})


# @pytest.mark.skip()
class Test_initiate_cooldown:
    @ pytest.fixture(scope='function')
    def setup(self, farm, minted_positions, pm,
              reward_token, funding_accounts, fn_isolation):
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, minted_positions, pm)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            _ = farm.claimRewards(i, {'from': deployer})

        return deposit

    def test_no_lockup(self, farm, setup):
        if (farm.cooldownPeriod() == 0):
            with reverts('Can not initiate cooldown'):
                farm.initiateCooldown(
                    0,
                    {'from': deployer}
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
                {'from': deployer}
            )

    def test_initiate_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': deployer}
            )


# @pytest.mark.skip()
class Test_withdraw:
    @pytest.fixture(scope='function')
    def setup(self, farm, minted_positions, pm,
              reward_token, funding_accounts, fn_isolation):
        claimed = list()
        _ = add_rewards(farm, reward_token, funding_accounts)
        _ = set_rewards_rate(farm, reward_token)
        deposit = create_deposits(farm, minted_positions, pm)
        chain.mine(10, None, 86400)
        for i in range(len(deposit)):
            claimed.append(farm.claimRewards(i, {'from': deployer}))

        return deposit, claimed

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.withdraw(
                len(setup) + 1,
                {'from': deployer}
            )

    def test_farm_paused(self, farm, setup):
        withdraw_txns = list()
        farm.farmPauseSwitch(True, {'from': deployer})
        for i in range(len(setup)):
            withdraw_txns.append(farm.withdraw(0, {'from': deployer}))

    def test_cooldown_not_initiated(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            with reverts('Please initiate cooldown'):
                for i in range(len(setup)):
                    farm.withdraw(0, {'from': deployer})

    def test_deposit_in_cooldown(self, farm, setup):
        if (farm.cooldownPeriod() != 0):
            farm.initiateCooldown(
                0,
                {'from': deployer}
            )
            with reverts('Deposit is in cooldown'):
                farm.withdraw(
                    0,
                    {'from': deployer}
                )

    def test_withdraw(self, setup, farm):
        withdraws = list()
        if (farm.cooldownPeriod() != 0):
            for i in range(len(setup)):
                farm.initiateCooldown(
                    0,
                    {'from': deployer}
                )
                chain.mine(10, farm.deposits(deployer, 0)['expiryDate'] + 10)
                withdraws.append(farm.withdraw(0, {'from': deployer}))

        if (farm.cooldownPeriod() == 0):
            for i in range(len(setup)):
                withdraws.append(farm.withdraw(0, {'from': deployer}))
