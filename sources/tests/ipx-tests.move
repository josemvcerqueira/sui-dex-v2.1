#[test_only]
module ipx::ipx_tests {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{mint_for_testing as mint, destroy_for_testing as burn};

  use ipx::ipx::{Self, IPXStorage, AccountStorage, IPXAdmin};
  use ipx::test_utils::{people, scenario};
  
  const START_EPOCH: u64 = 4;
  const LPCOIN_ALLOCATION_POINTS: u64 = 500;

  struct LPCoin {}

  fun test_stake_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      let coin_ipx = ipx::stake(&mut ipx_storage, &mut account_storage, mint<LPCoin>(500, ctx(test)), ctx(test));

      assert!(burn(coin_ipx) == 0, 0);

      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };
  }


  #[test]
  fun test_stake() {
    let scenario = scenario();
    test_stake_(&mut scenario);
    test::end(scenario);
  }

  fun register_token(test: &mut Scenario) {
    let (owner, _) = people();

    next_tx(test, owner);
    {
      ipx::init_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let admin_cap = test::take_from_sender<IPXAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      ipx::add_pool<LPCoin>(&admin_cap, &mut ipx_storage, &mut account_storage, LPCOIN_ALLOCATION_POINTS, false, ctx(test));

      test::return_shared(ipx_storage);
      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
    }
  }
}