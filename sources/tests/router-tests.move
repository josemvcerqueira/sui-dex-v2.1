#[test_only]
module ipx::router_tests {
  
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{mint_for_testing as mint, destroy_for_testing as burn};

  use ipx::router;
  use ipx::dex_stable::{Self as stable, Storage as SStorage};
  use ipx::dex_volatile::{Self as volatile, Storage as VStorage};
  use ipx::test_utils::{people, scenario};

  struct USDT {}
  struct USDC {}
  struct BTC {}

  fun test_selects_volatile_if_no_stable_pool_(test: &mut Scenario) {
    let (alice, _) = people();

    let usdc_amount = 220000000 * 1000000;
    let btc_amount = 10000 * 1000000000;
    
    next_tx(test, alice);
    {
      volatile::init_for_testing(ctx(test));
      stable::init_for_testing(ctx(test));
    };

    next_tx(test, alice);
    {
     let storage = test::take_shared<VStorage>(test);

        let lp_coin = volatile::create_pool(
          &mut storage,
          mint<BTC>(btc_amount, ctx(test)),
          mint<USDC>(usdc_amount, ctx(test)),
          ctx(test)
        );

        burn(lp_coin);
        test::return_shared(storage);
    };

     next_tx(test, alice);
     {
      let v_storage = test::take_shared<VStorage>(test);
      let s_storage =test::take_shared<SStorage>(test);

      let pred = router::is_volatile_better<BTC, USDC>(
        &v_storage,
        &s_storage,
        2,
        0
      );

      assert!(pred, 0);
      test::return_shared(v_storage);
      test::return_shared(s_storage);
     }
  }

  #[test] 
  fun test_selects_volatile_if_no_stable_pool() {
    let scenario = scenario();
    test_selects_volatile_if_no_stable_pool_(&mut scenario);
    test::end(scenario);
  }
}