from brownie import (
    FarmFactory,
    TransparentUpgradeableProxy,
    Contract,
    accounts,
    UniswapFarmV1Deployer,
    ProxyAdmin,
    reverts,
    UniswapFarmV1,
    chain
)
import brownie
import pytest
import eth_utils
from conftest import (
    GAS_LIMIT,
    deploy_uni_farm,
    init_farm,
    token_obj,
    fund_account,
    constants,
)

# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']
global token_A, token_B, rwd_token, deployer


@pytest.fixture(scope='module', autouse=True)
def setUp():
    global deployer
    deployer = accounts[0]


@pytest.fixture(scope='module', autouse=True, params=farm_names)
def config(request):
    global farm_name
    farm_name = request.param
    farm_config = constants[farm_name]
    config = farm_config['config']
    return config


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
    print("factory owner is:", factory_contract.owner())
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
def farm(config):
    uniswap_farm = deploy_uni_farm(deployer, UniswapFarmV1)
    return init_farm(deployer, uniswap_farm, config)


# @pytest.fixture(scope='module', autouse=True)
# def farm(config, farm_deployer):
#     tx = farm_deployer.createFarm(
#         (
#             deployer,
#             config['farm_start_time'],
#             config['cooldown_period'],
#             list(config['uniswap_pool_data'].values()),
#             list(
#                 map(
#                     lambda x: list(x.values()),
#                     config['reward_token_data']
#                 )
#             ),
#         ),
#         {'from': deployer}
#     )
#     return UniswapFarmV1.at(tx.new_contracts[0])


class Test_initialization:
    def test_intitialization_invalid_farm_start_time(
        self, farm_deployer, config
    ):
        with reverts('Invalid farm startTime'):
            farm_deployer.createFarm(
                (deployer,
                 brownie.chain.time()-1,
                 config['cooldown_period'],
                 list(config['uniswap_pool_data'].values()),
                 list(map(lambda x: list(x.values()),
                          config['reward_token_data']))),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )

    def test_intitialization_invalid_cooldown_period(
        self, farm_deployer, config
    ):
        with reverts('Cooldown < MinCooldownPeriod'):
            farm_deployer.createFarm(
                (
                    deployer,
                    brownie.chain.time()+1000,
                    1,
                    list(config['uniswap_pool_data'].values()),
                    list(map(lambda x: list(x.values()),
                             config['reward_token_data']))
                ),
                {'from': deployer, 'gas_limit': GAS_LIMIT},
            )


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
                farm.recoverERC20(token_obj('frax'), {'from': accounts[4]})

        def test_recoverERC20_reward_token(self, farm):
            with reverts('Can\'t withdraw rewardToken'):
                farm.recoverERC20(token_obj('spa'), {'from': deployer})

        def test_recoverERC20_zero_balance(self, farm):
            with reverts('Can\'t withdraw 0 amount'):
                farm.recoverERC20(token_obj('frax'), {'from': deployer})

        def test_recoverERC20(self, farm):
            balance = 100 * 1e18
            fund_account(farm, 'frax', balance)
            beforeRecovery = token_obj('frax').balanceOf(deployer)
            tx = farm.recoverERC20(token_obj('frax'), {'from': deployer})
            afterRecovery = token_obj('frax').balanceOf(deployer)
            event = tx.events['RecoveredERC20']
            assert event['token'] == token_obj('frax')
            assert event['amount'] == balance
            assert afterRecovery - beforeRecovery == balance


@pytest.mark.skip()
class Test_view_functions:
    class Test_compute_rewards:
        def test_computeRewards_invalid_deposit(self):
            # Should revert if the deposit is invalid
            pass

        def test_computeRewards_before_farm_starts(self):
            # No rewards should be accrued
            pass

        def test_computeRewards_after_farm_starts(self):
            # Normal case
            pass

    def test_getNumDeposits(self):
        pass

    def test_getDeposit(self):
        pass

    def test_getNumSubscriptions(self):
        pass

    class Test_get_subscription_info:
        def test_getSubscriptionInfo_invalid_subscriptio(self):
            # Should revert with subscription does not exist
            pass

        def test_getSubscriptionInfo(self):
            pass

    def test_getRewardRates(self):
        pass

    def test_getRewardFundInfo(self):
        pass

    class Test_get_reward_balance:
        def test_getRewardBalance_invalid_rwdToken(self):
            # Should revert when _rwdToken is invalid
            pass

        def test_getRewardBalance_rewardsAcc_more_than_supply(self):
            pass

        def test_getRewardBalance(self):
            # normal case
            pass


@pytest.mark.skip()
class Test_recover_reward_funds:
    def test_unauthorized_call(self):
        pass

    def test_recover_reward_funds(self):
        pass


@pytest.mark.skip()
class Test_set_reward_rate:
    def test_unauthorized_call(self):
        pass

    def test_set_reward_rate(self):
        pass


@pytest.mark.skip()
class Test_add_rewards:
    def test_invalid_reward(self):
        pass

    def test_add_rewards(self):
        pass


@pytest.mark.skip()
class Test_deposit:
    def test_not_paused(self):
        pass

    def test_call_not_via_NFTM(self):
        pass

    def test_empty_data(self):
        pass

    def test_lockup_disabled(self):
        # Test applicable for no-lockup farm
        pass

    def test_successful_deposit_with_lockup(self):
        pass

    def test_successful_deposit_without_lockup(self):
        pass


@pytest.mark.skip()
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


@pytest.mark.skip()
class Test_withdraw:
    @ pytest.fixture(scope='function')
    def setup(self):
        # create a deposit here
        pass

    def test_invalid_deposit_id(self):
        pass

    def test_cooldown_not_initiated(self, setup):
        pass

    def test_deposit_in_cooldown(self, setup):
        pass

    def test_withdraw(self, setup):
        pass


@pytest.mark.skip()
class Test_claim_rewards:
    @ pytest.fixture(scope='function')
    def setup(self):
        # create a deposit here
        pass

    def test_invalid_deposit_id(self):
        pass

    def test_not_in_emergency(self):
        pass

    def test_claim_rewards_for_self(self, setup):
        pass

    def test_claim_rewards_for_other_address(self, setup):
        pass

    def test_multiple_reward_claims(self, setup):
        pass
