from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    UniswapFarmV1Deployer,
    ProxyAdmin,
    reverts,
    UniswapFarmV1,
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
    init_farm,
    token_obj,
    fund_account,
    constants,
    test_constants,

)

# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_without_lockup', 'test_farm_with_lockup']


@pytest.fixture(scope='module', autouse=True)
def setUp(config):
    global deployer, not_rwd_tkn, reward_tokens, lock_data
    global no_lock_data, manager
    deployer = accounts[0]
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
    print('Deploy UniswapFarmV1Deployer contract.')
    farm_deployer = UniswapFarmV1Deployer.deploy(factory, {'from': deployer})

    print('Register the deployer contract with the Factory.')
    factory.registerFarmDeployer(
        farm_deployer,
        {'from': deployer}
    )
    return farm_deployer


@pytest.fixture(scope='module', autouse=True)
def farm_contract(config):
    return deploy_uni_farm(deployer, UniswapFarmV1)


@pytest.fixture(scope='module')
def farm(config, farm_contract):
    return init_farm(deployer, farm_contract, config)


@pytest.fixture(scope='module', autouse=True)
def funding_accounts(test_config):
    token = list(test_config['funding_data'].keys())
    amount = list(test_config['funding_data'].values())
    for i in range(len(token)):
        fund_account(deployer, token[i], amount[i])
    # fund_account(accounts[i], token[i], amount[i]) #for multi user funding
        print(token[i], 'is funded ', amount[i])
    print(token, amount)
    return token, amount


@pytest.fixture(scope='module', autouse=True)
def reward_token(config):
    reward_tokens = list()
    reward_tokens.append(token_obj('spa'))  # Default reward token
    for i in range(len(config['reward_token_data'])):
        reward_tokens.append(interface.ERC20(
            config['reward_token_data'][i]['reward_tkn']))
    for i in range(len(reward_tokens)):
        rwd_token_name = reward_tokens[i].name()
        print('reward token name is: ', rwd_token_name)
    return reward_tokens


def add_rewards(farm, reward_token, funding_accounts):
    farm_rewards = list()
    key, amount = funding_accounts
    for i in range(len(reward_token)):
        token_obj(key[i]).approve(farm, 2*amount[i], {'from': deployer})
        farm_rewards.append(farm.addRewards(
            reward_token[i], 10000*10**reward_token[i].decimals(),
            {'from': deployer}))
    return farm_rewards


def set_rewards_rate(farm, reward_token):
    rewards_rate = list()
    if (farm.cooldownPeriod() != 0):
        for i in range(len(reward_token)):
            rwd_amt_no_lock = 1e-3*10**reward_token[i].decimals()
            rwd_amt_lock = 2*rwd_amt_no_lock
            tx = farm.setRewardRate(reward_token[i],
                                    [rwd_amt_no_lock,
                                    rwd_amt_lock],
                                    {'from': manager})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] == \
                rwd_amt_no_lock
            assert tx.events['RewardRateUpdated']['newRewardRate'][1] ==\
                rwd_amt_lock
        print('rewards rate changed and checked!!')
        return rewards_rate
    if (farm.cooldownPeriod() == 0):
        for i in range(len(reward_token)):
            rwd_amt_no_lock = 1e-3*10**reward_token[i].decimals()
            tx = farm.setRewardRate(reward_token[i],
                                    [rwd_amt_no_lock],
                                    {'from': manager})
            rewards_rate.append(tx)
            assert tx.events['RewardRateUpdated']['newRewardRate'][0] ==\
                rwd_amt_no_lock
        print('rewards rate changed and checked!!')
        return rewards_rate


@pytest.fixture(scope='module', autouse=True)
def minted_position(config, test_config, position_manager):
    global amount_a, amount_b
    token_id = list()
    amount_a = list()
    amount_b = list()
    token_a_obj = interface.ERC20(config['uniswap_pool_data']['token_A'])
    token_b_obj = interface.ERC20(config['uniswap_pool_data']['token_B'])
    token_a_decimals = token_a_obj.decimals()
    token_b_decimals = token_b_obj.decimals()

    for i in range(test_config['number_of_deposits']):
        amount_a.append(randint(100, 1000) * 10 ** token_a_decimals)
        amount_b.append(randint(100, 1000) * 10 ** token_b_decimals)
        minting = mint_position(
            position_manager,
            token_a_obj,
            token_b_obj,
            config['uniswap_pool_data']['fee_tier'],
            config['uniswap_pool_data']['lower_tick'],
            config['uniswap_pool_data']['upper_tick'],
            amount_a[i],
            amount_b[i],
            deployer,
        )
        token_id.append(minting)
    print(token_id)
    return token_id


def deposited(farm, minted_position, position_manager):
    """
    This helper function deposits into farms
    """

    token_id = minted_position
    print('token Ids are: ', token_id)
    tx = list()
    if (farm.cooldownPeriod() != 0):
        print('lockup deposit')
        for i in range(len(token_id)):
            deposit_txn = position_manager.safeTransferFrom(
                deployer,
                farm.address,
                token_id[i],
                lock_data,
                {'from': deployer},
            )
            tx.append(deposit_txn)
        for i in range(len(tx)):
            assert tx[i].events['Deposited']['account'] == deployer
            assert tx[i].events['Deposited']['tokenId'] == minted_position[i]
            assert tx[i].events['Transfer']['to'] == farm.address
            assert tx[i].events['Deposited']['locked'] is True

        print('Deposit checks passed ✅✅')
        return tx
    elif (farm.cooldownPeriod() == 0):
        print('no lockup deposit')
        for i in range(len(token_id)):
            deposit_txn = position_manager.safeTransferFrom(
                deployer,
                farm.address,
                token_id[i],
                no_lock_data,
                {'from': deployer},
            )
            tx.append(deposit_txn)
        for i in range(len(tx)):
            assert tx[i].events['Deposited']['account'] == deployer
            assert tx[i].events['Deposited']['tokenId'] == minted_position[i]
            assert tx[i].events['Transfer']['to'] == farm.address
            assert tx[i].events['Deposited']['locked'] is False
        print('Deposit checks passed ✅✅')
        return tx


# @pytest.mark.skip()
class Test_initialization:
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
        with reverts('Cooldown < MinCooldownPeriod'):
            farm_contract.initialize(
                config['farm_start_time'],
                1,
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
                with reverts('Cooldown period too low'):
                    farm.updateCooldownPeriod(
                        1, {'from': deployer, 'gas_limit': GAS_LIMIT})

        def test_cooldown(self, farm):
            if (farm_name == 'test_farm_with_lockup'):
                tx = farm.updateCooldownPeriod(
                    5, {'from': deployer, 'gas_limit': GAS_LIMIT})
                event = tx.events['CooldownPeriodUpdated']
                assert event['newCooldownPeriod'] == 5
                assert event['oldCooldownPeriod'] == 21
                assert farm.cooldownPeriod() == 5

    class Test_update_farm_start_time:
        def test_updateFarmStartTime_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.updateFarmStartTime(
                    chain.time() + 2, {'from': accounts[2]})

        def test_updateFarmStartTime_for_started_farm(self, farm):
            chain.sleep(2500)
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
            with reverts('Farm is paused'):
                farm.initiateCooldown(2, {'from': accounts[2]})

        def test_farmPauseSwitch_unpause(self, farm):
            farm.farmPauseSwitch(
                True, {'from': deployer})
            tx = farm.farmPauseSwitch(
                False, {'from': deployer})
            event = tx.events['FarmPaused']
            assert not event['paused']

    class Test_close_farm:
        def test_closeFarm_only_admin(self, farm):
            with reverts('Ownable: caller is not the owner'):
                farm.closeFarm({'from': accounts[3]})

        def test_closeFarm(self, farm):
            farm.closeFarm({'from': deployer})
            with reverts('Farm closed'):
                farm.claimRewards(
                    accounts[2], 2, {'from': accounts[2]})

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
    class Test_compute_rewards:
        def test_computeRewards_invalid_deposit(self, farm, minted_position,
                                                position_manager):
            deposit = deposited(farm, minted_position, position_manager)
            with reverts('Deposit does not exist'):
                farm.computeRewards(deployer, len(deposit)+1)

        def test_computeRewards_after_farm_starts(self, farm, minted_position,
                                                  funding_accounts, position_manager, reward_token):
            rewards = list()
            added_rewards = add_rewards(farm, reward_token, funding_accounts)
            rate = set_rewards_rate(farm, reward_token)
            deposit = deposited(farm, minted_position, position_manager)
            chain.mine(10, None, 86400)
            for i in range(len(deposit)):
                tx = farm.computeRewards(deployer, i)
                rewards.append(tx)
                print('rewards calculated for deposit ',
                      i, 'are: ', rewards[i])
            added_rewards
            rate

    def test_getNumDeposits(self, farm, minted_position, position_manager):

        deposit = deposited(farm, minted_position, position_manager)
        assert farm.getNumDeposits(deployer) == len(deposit)

    def test_getLiquidity(self, farm, minted_position, position_manager):
        for i in range(len(minted_position)):
            liquidity = farm._getLiquidity(minted_position[i],
                                           {'from': deployer})
            assert liquidity == position_manager.positions(minted_position[i])[
                7]
        print('get liquidity checks passed')

    def test_getLiquidity_incorrect_pool_tkn(self, farm):
        with reverts('Incorrect pool token'):
            farm._getLiquidity(117684)

    def test_getLiquidity_incorrect_tick_range(self, farm, position_manager):
        with reverts('Incorrect pool token'):
            farm._getLiquidity(117684)

    def test_getNumSubscriptions(self):
        pass

    def test_invalid_uniswap_tick_ranges(self, farm):
        with reverts('Invalid tick range'):
            farm._validateTickRange(-887220, -887220)
        with reverts('Invalid tick range'):
            farm._validateTickRange(-887273, 887210)
        with reverts('Invalid tick range'):
            farm._validateTickRange(-887219, 887210)
        with reverts('Invalid tick range'):
            farm._validateTickRange(-887220, 887273)
        with reverts('Invalid tick range'):
            farm._validateTickRange(-887220, 887219)
        pass

    def test_zero_address(self, farm):
        with reverts('Invalid address'):
            farm._isNonZeroAddr(ZERO_ADDRESS, {'from': deployer})

    class Test_get_subscription_info:
        def test_getSubscriptionInfo_invalid_subscription(self, farm,
                                                          minted_position):
            id_minted = minted_position
            with reverts('Subscription does not exist'):
                farm.getSubscriptionInfo(id_minted[0], 3)

        def test_getSubscriptionInfo(self):
            pass

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

    class Test_get_reward_fund_info:
        def test_getRewardFundInfo_more_than_added(self, farm):
            with reverts('Reward fund does not exist'):
                farm.getRewardFundInfo(3)

        def test_getRewardFundInfo(self, farm):
            res = farm.getRewardFundInfo(0)
            print(res)
            if(farm_name == 'test_farm_with_lockup'):
                res = farm.getRewardFundInfo(1)
                print(res)

    class Test_get_reward_balance:
        def test_getRewardBalance_invalid_rwdToken(self, farm):
            with reverts('Invalid _rwdToken'):
                farm.getRewardBalance(not_rwd_tkn, {'from': deployer})

        def test_getRewardBalance_rewardsAcc_more_than_supply(self):
            pass

        def test_getRewardBalance(self):
            # normal case
            pass


# @pytest.mark.skip()
class Test_recover_reward_funds:
    def test_unauthorized_call(self):
        pass

    def test_recover_reward_funds(self):
        pass


# @pytest.mark.skip()
class Test_set_reward_rate:
    def test_unauthorized_call(self):
        pass

    def test_set_reward_rate(self, farm, reward_token):
        set_rewards_rate(farm, reward_token)


# @pytest.mark.skip()
class Test_add_rewards:
    def test_invalid_reward(self, farm):
        with reverts('Invalid reward token'):
            farm.addRewards(ZERO_ADDRESS, 10e2, {'from': deployer})

    def test_add_rewards(self, farm, reward_token, funding_accounts):
        tx = add_rewards(farm, reward_token, funding_accounts)

        for i in range(len(reward_token)):
            assert reward_token[i].address == \
                tx[i].events['RewardAdded']['rwdToken']
            assert tx[i].events['RewardAdded']['amount'] == 10000 * \
                10**reward_token[i].decimals()
            print('Reward token', reward_token[i].name(), 'is checked!!')
            assert tx[i].events['Transfer']['from'] == deployer
            print('checked the spender for the reward token',
                  reward_token[i].name())


# @pytest.mark.skip()
class Test_deposit:
    def test_not_paused(self):
        pass

    def test_call_not_via_NFTM(self, farm, minted_position):
        token_id = minted_position
        with reverts('onERC721Received: not a univ3 nft'):
            farm.onERC721Received(
                accounts[2],
                deployer,
                token_id[0],
                no_lock_data,
                {'from': deployer},
            )

    def test_empty_data(self, farm, minted_position, position_manager):
        token_id = minted_position
        if (farm.cooldownPeriod() != 0):
            with reverts('onERC721Received: no data'):
                position_manager.safeTransferFrom(
                    deployer,
                    farm.address,
                    token_id[0],
                    {'from': deployer})

    def test_lockup_disabled(self, farm, minted_position, position_manager):
        token_id = minted_position
        print('token Ids are: ', token_id)
        if (farm.cooldownPeriod() == 0):
            with reverts('Lockup functionality is disabled'):
                farm.onERC721Received(
                    accounts[2],
                    deployer,
                    token_id[0],
                    lock_data,
                    {'from': position_manager.address},
                )

    def test_successful_deposit_with_lockup(self, farm, minted_position, position_manager):
        tx = deposited(farm, minted_position, position_manager)
        print('amount A', amount_a)
        print('amount B', amount_b)
        tx

    def test_successful_deposit_without_lockup(self, farm, minted_position, position_manager):

        tx = deposited(farm, minted_position, position_manager)
        print('amount A', amount_a)
        print('amount B', amount_b)
        tx
# # @pytest.mark.skip()


class Test_claim_rewards:
    @pytest.fixture()
    def setup(self, farm, minted_position, position_manager, reward_token, funding_accounts):
        reward = add_rewards(farm, reward_token, funding_accounts)
        rate = set_rewards_rate(farm, reward_token)
        tx = deposited(farm, minted_position, position_manager)
        chain.mine(10, None, 86400)
        return tx

    def test_invalid_deposit_id(self, farm, setup):
        with reverts('Deposit does not exist'):
            farm.claimRewards(
                len(setup)+1,
                {'from': deployer}
            )

    def test_not_in_emergency(self, farm, setup):
        pass

    def test_claim_rewards_for_self(self, farm, setup):
        for i in range(len(setup)):
            tx = farm.claimRewards(i, {'from': deployer})

    def test_claim_rewards_for_other_address(self, farm, setup):
        with reverts('Deposit does not exist'):
            tx = farm.claimRewards(0, {'from': accounts[2]})

    def test_multiple_reward_claims(self, farm, setup):
        for i in range(len(setup)):
            tx = farm.claimRewards(i, {'from': deployer})
        chain.mine(10, None, 86400)
        for i in range(len(setup)):
            tx = farm.claimRewards(i, {'from': deployer})

        for i in range(len(setup)):
            tx = farm.claimRewards(i, {'from': deployer})
        for i in range(len(setup)):
            tx = farm.claimRewards(i, {'from': deployer})

    def test_claiming_without_rewards(self, farm, minted_position, position_manager):
        tx = deposited(farm, minted_position, position_manager)
        chain.mine(10, None, 86400)
        for i in range(len(tx)):
            tx = farm.claimRewards(i, {'from': deployer})


# @pytest.mark.skip()
class Test_initiate_cooldown:
    # skip tests for no-lockup farm
    def test_not_in_emergency(self):
        pass

    def test_invalid_deposit_id(self):
        pass

    def test_for_unlocked_deposit(self):
        pass

    def test_initiate_cooldown(self):
        pass


# @pytest.mark.skip()
class Test_withdraw:
    @ pytest.fixture(scope='function')
    def setup(self, farm, minted_position, position_manager):
        tx = deposited(farm, minted_position, position_manager)
        print('withdraw deposit: ', deposited)
        return tx

    def test_invalid_deposit_id(self):
        pass

    def test_cooldown_not_initiated(self, setup):
        pass

    def test_deposit_in_cooldown(self, setup):
        pass

    def test_withdraw(self, setup):
        pass
