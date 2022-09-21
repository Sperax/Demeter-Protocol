from brownie import (
    UniswapFarmV1,
)
import pytest
from conftest import (
    deploy,
    owner,
    fund_account,
    constants,
    token_obj,
)

# import scripts.deploy_farm as farm_deployer
# from ..scripts.constants import demeter_farm_constants

farm_names = ['test_farm_with_lockup', 'test_farm_without_lockup']
global farm, token_A, token_B, rwd_token


@pytest.fixture(scope='module', autouse=True, params=farm_names)
def farm_setup(request):
    global farm, token_A, token_B, rwd_token
    farm_name = request.param
    farm_config = constants[farm_name]
    token_A = token_obj(farm_config['token_A'])
    token_B = token_obj(farm_config['token_B'])
    rwd_token = map(lambda x: token_obj(x), farm_config['reward_tokens'])
    config = farm_config['config']
    print('Deploying Farm')
    farm = deploy(owner, UniswapFarmV1, config)

    token_a_dec = token_A.decimals()
    token_b_dec = token_B.decimals()
    fund_account(owner, farm_config['token_A'], 2e5 * 10 ** token_a_dec)
    fund_account(owner, farm_config['token_B'], 2e5 * 10 ** token_b_dec)

    token_A.approve(farm, 1e6 * 10 ** token_a_dec, {'from': owner})
    token_B.approve(farm, 1e6 * 10 ** token_b_dec, {'from': owner})

    print('Funding rewards to farm')
    farm.addRewards(token_A, 1e5 * 10 ** token_a_dec, {'from': owner})
    farm.addRewards(token_B, 1e5 * 10 ** token_b_dec, {'from': owner})
    yield farm_setup


def test_intitialization():
    pass


class Test_admin_function:
    class Test_update_cooldown:
        def test_updateCooldownPeriod_only_admin(self):
            # Should revert when called with a non owner account
            pass

        def test_farm_with_no_cooldown(self):
            # Should revert
            pass

        def test_incorrect_cooldown(self):
            # should revert
            pass

        def test_cooldown(self):
            pass

    class Test_update_farm_start_time:
        def test_updateFarmStartTime_only_admin(self):
            # Should revert when called with a non owner account
            pass

        def test_updateFarmStartTime_for_started_farm(self):
            # Should revert if farm is already started
            pass

        def test_updateFarmStartTime_in_past(self):
            # Should revert when _newStartTime is lesser than now
            pass

        def test_updateFarmStartTime(self):
            # Should pass when farmStartTime is > now and _newStartTime > now
            pass

    class Test_add_reward_token:
        def test_addRewardToken_only_admin(self):
            # Should revert when called with a non owner account
            pass

        def test_addRewardToken_more_than_max(self):
            # Should revert when we try to add more than MAX_NUM_REWARDS
            pass

        def test_addRewardToken_invalid_token(self):
            # Should revert When token is a zero address
            pass

        def test_addRewardToken_invalid_manager(self):
            # Should revert When token manager is a zero address
            pass

        def test_addRewardToken_already_registered(self):
            # Should revert when trying to register an already registered token
            pass

        def test_addRewardToken_spa(self):
            # Should skip token manager passed and set SPA_TOKEN_MANAGER
            # from the constants of the contract
            pass

        def test_addRewardToken(self):
            # Should set data properly for tokens other than SPA
            pass

    class Test_farm_pause_switch:
        def test_farmPauseSwitch_only_admin(self):
            # Should revert when called with a non owner account
            pass

        def test_farmPauseSwitch_try_false(self):
            # Should revert when isPaused is already paused and
            # we again pass false
            pass

        def test_farmPauseSwitch_pause(self):
            # Should pause the farm when passed _isPaused as true and
            # other functions which use notPaused modifier should revert
            pass

        def test_farmPauseSwitch_unpause(self):
            # unpause a paused farm and try to do operations normally
            pass

    class Test_close_farm:
        def test_closeFarm_only_admin(self):
            # Should revert when called with a non owner account
            pass

        def test_closeFarm(self):
            # Should close farm and other functions using farmNotClosed
            # modifier should revert
            pass

    class Test_recover_ERC20:
        def test_recoverERC20_only_admin(self):
            # Should revert when called by a non owner account
            pass

        def test_recoverERC20_reward_token(self):
            # Should revert when owner tries to withdraw an added reward token
            pass

        def test_recoverERC20_zero_balance(self):
            # Should revert when owner tries to withdraw a token
            # whose balance is 0
            pass

        def test_recoverERC20(self):
            # Owner should be able to withdraw any other ERC20 apart from
            # reward tokens, sitting in the farm.
            pass


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


class Test_recover_reward_funds:
    def test_unauthorized_call(self):
        pass

    def test_recover_reward_funds(self):
        pass


class Test_set_reward_rate:
    def test_unauthorized_call(self):
        pass

    def test_set_reward_rate(self):
        pass


class Test_add_rewards:
    def test_invalid_reward(self):
        pass

    def test_add_rewards(self):
        pass


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


class Test_initiate_cooldown:
    # skip tests for no-lockup farm
    def test_not_in_emergency(self):
        if(farm.cooldownPeriod() == 0):
            pytest.skip('No cooldown for this farm')

    def test_invalid_deposit_id(self):
        pass

    def test_for_unlocked_deposit(self):
        pass

    def test_initiate_cooldown(self):
        pass


class Test_withdraw:
    @pytest.fixture(scope='function')
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


class Test_claim_rewards:
    @pytest.fixture(scope='function')
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
