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
        def test_farm_with_no_cooldown(self):
            # Should revert
            pass

        def test_incorrect_cooldown(self):
            # should revert
            pass

        def test_cooldown(self):
            pass

    class Test_toggle_deposit:
        def test_unauthorized_call(self):
            pass

        def test_toggle(self):
            pass

    class Test_declare_emergency:
        def test_unauthorized_call(self):
            pass

        def test_declare_emergency(self):
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


class Test_view_functions:
    # @pytest.fixture(scope='function', autouse=True)
    # def setup(self):
    #     # create a deposit here
    #     pass

    class Test_get_num_deposits:
        def test_get_num_deposits(self):
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
