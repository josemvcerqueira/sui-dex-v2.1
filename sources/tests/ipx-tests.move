#[test_only]
module ipx::ipx_tests {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{Self, mint_for_testing as mint, destroy_for_testing as burn, CoinMetadata};
  use sui::tx_context;

  use ipx::ipx::{Self, IPXStorage, AccountStorage, IPXAdmin, IPX};
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

  fun test_init_(test: &mut Scenario) {
    let (owner, _) = people();

    next_tx(test, owner);
    {
      ipx::init_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let metadata = test::take_immutable<CoinMetadata<IPX>>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let decimals = coin::get_decimals<IPX>(&metadata);

      let (supply, ipx_per_epoch, total_allocation_points, start_epoch) = ipx::get_ipx_storage_info(&ipx_storage);

      let (allocation_points, last_reward_epoch, accrued_ipx_per_share, balance) = ipx::get_pool_info<IPX>(&ipx_storage);

      assert!(decimals == 9, 0);
      assert!(supply == 0, 0);
      assert!(ipx_per_epoch == 100000000000, 0);
      assert!(total_allocation_points == 1000, 0);
      assert!(start_epoch == 4, 0);
      assert!(allocation_points == 1000, 0);
      assert!(last_reward_epoch == tx_context::epoch(ctx(test)), 0);
      assert!(accrued_ipx_per_share == 0, 0);
      assert!(balance == 0, 0);

      test::return_immutable(metadata);
      test::return_shared(ipx_storage);
    };
  }

  #[test]
  fun test_init() {
    let scenario = scenario();
    test_init_(&mut scenario);
    test::end(scenario);
  }

  fun test_add_pool_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (lp_coin_allocation_points, last_reward_epoch, accrued_ipx_per_share, balance) = ipx::get_pool_info<LPCoin>(&ipx_storage);
      let (ipx_allocation_points, _, _, _) = ipx::get_pool_info<IPX>(&ipx_storage);
      let (_, _, total_allocation_points, _) = ipx::get_ipx_storage_info(&ipx_storage);

      let ipx_allocation = LPCOIN_ALLOCATION_POINTS / 3;

      assert!(lp_coin_allocation_points == LPCOIN_ALLOCATION_POINTS, 0);
      assert!(last_reward_epoch == START_EPOCH, 0);
      assert!(accrued_ipx_per_share == 0, 0);
      assert!(balance == 0, 0);
      assert!(ipx_allocation_points == ipx_allocation, 0);
      assert!(total_allocation_points == LPCOIN_ALLOCATION_POINTS + ipx_allocation, 0);

      test::return_shared(ipx_storage);
    };
  }

  #[test]
  fun test_add_pool() {
    let scenario = scenario();
    test_add_pool_(&mut scenario);
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
    };
  }
}