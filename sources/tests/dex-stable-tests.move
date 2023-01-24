#[test_only]
module ipx::dex_stable_tests {

    use sui::coin::{Self, mint_for_testing as mint, destroy_for_testing as burn};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::math;

    use ipx::dex_stable::{Self as dex, Storage, AdminCap, SLPCoin};
    use ipx::test_utils::{people, scenario};

    struct USDT has drop {}
    struct USDC has drop {}

    const USDT_DECIMAL_SCALAR: u64 = 1000000000; // 9 decimals
    const INITIAL_USDT_VALUE: u64 = 100 * 1000000000; //100 * 1e9
    const USDC_DECIMAL_SCALAR: u64 = 1000000; // 6 decimals
    const INITIAL_USDC_VALUE: u64 = 100 * 1000000;
    const ZERO_ACCOUNT: address = @0x0;

    fun test_create_pool_(test: &mut Scenario) {
      let (alice, _) = people();

      let initial_k = dex::get_k(INITIAL_USDT_VALUE, INITIAL_USDC_VALUE, USDT_DECIMAL_SCALAR, USDC_DECIMAL_SCALAR);
      let lp_coin_initial_user_balance = math::sqrt(initial_k);

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let admin_cap = test::take_from_address<AdminCap>(test, alice);

        let lp_coin = dex::create_pool(
          &admin_cap,
          &mut storage,
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          mint<USDT>(INITIAL_USDT_VALUE, ctx(test)),
          6,
          9,
          ctx(test)
        );

        assert!(burn(lp_coin) == lp_coin_initial_user_balance, 0);
        test::return_shared(storage);
        test::return_to_address(alice, admin_cap);
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, supply) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<USDC, USDT>(&storage);
        let (decimals_x, decimals_y) = dex::get_pool_metadata<USDC, USDT>(&storage);

        assert!(supply == lp_coin_initial_user_balance + 10, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE, 0);
        assert!(usdt_reserves == INITIAL_USDT_VALUE, 0);
        assert!(k_last == initial_k, 0);
        assert!(decimals_x == USDC_DECIMAL_SCALAR, 0);
        assert!(decimals_y == USDT_DECIMAL_SCALAR, 0);

        test::return_shared(storage);
      }
    }

    #[test]
    fun test_create_pool() {
        let scenario = scenario();
        test_create_pool_(&mut scenario);
        test::end(scenario);
    }

    fun test_swap_token_x_(test: &mut Scenario) {
       test_create_pool_(test);

       let (_, bob) = people();

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let usdc_amount = INITIAL_USDC_VALUE / 10;

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdc_amount - ((usdc_amount * 50) / 100000);
        // 9086776671
        let v_usdt_amount_received = (usdt_reserves * token_in_amount) / (token_in_amount + usdc_reserves);
        // calculated off chain to save time
        let s_usdt_amount_received = 9990015154;


        let usdt = dex::swap_token_x<USDC, USDT>(
          &mut storage,
          mint<USDC>(usdc_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdt) == s_usdt_amount_received, 0);
        // 10% less slippage
        assert!(s_usdt_amount_received > v_usdt_amount_received, 0);
        
        test::return_shared(storage);
       }
    }

    #[test]
    fun test_swap_token_x() {
        let scenario = scenario();
        test_swap_token_x_(&mut scenario);
        test::end(scenario);
    }

    fun test_swap_token_y_(test: &mut Scenario) {
       test_create_pool_(test);

       let (_, bob) = people();

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let usdt_amount = INITIAL_USDT_VALUE / 10;

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdt_amount - ((usdt_amount * 50) / 100000);
        // 9086776
        let v_usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + usdt_reserves);
        // calculated off chain to save time
        let s_usdc_amount_received = 9990015;


        let usdc = dex::swap_token_y<USDC, USDT>(
          &mut storage,
          mint<USDT>(usdt_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdc) == s_usdc_amount_received, 0);
        // 10% less slippage
        assert!(s_usdc_amount_received > v_usdc_amount_received, 0);
        
        test::return_shared(storage);
       }
    }

    #[test]
    fun test_swap_token_y() {
        let scenario = scenario();
        test_swap_token_y_(&mut scenario);
        test::end(scenario);
    }

    fun test_add_liquidity_(test: &mut Scenario) {
        test_create_pool_(test);
        remove_fee(test);

        let (_, bob) = people();

        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;

        next_tx(test, bob);
        {
        let storage = test::take_shared<Storage>(test);
        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (_, _, supply) = dex::get_amounts(pool);

        let lp_coin = dex::add_liquidity(
          &mut storage,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
          );

        let pool = dex::borrow_pool<USDC, USDT>(&storage); 
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool); 

        assert!(burn(lp_coin)== supply / 10, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE + usdc_value, 0);
        assert!(usdt_reserves == INITIAL_USDT_VALUE + usdt_value, 0);
        
        test::return_shared(storage);
        }   
    }

    #[test]
    fun test_add_liquidity() {
        let scenario = scenario();
        test_add_liquidity_(&mut scenario);
        test::end(scenario);      
    }

    fun test_remove_liquidity_(test: &mut Scenario) {
        test_create_pool_(test);
        remove_fee(test);

        let (_, bob) = people();

        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;

        next_tx(test, bob);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity(
            &mut storage,
            mint<USDC>(usdc_value, ctx(test)),
            mint<USDT>(usdt_value, ctx(test)),
            0,
            ctx(test)
          );

          let pool = dex::borrow_pool<USDC, USDT>(&storage);
          let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);

          let lp_coin_value = coin::value(&lp_coin);

          let (usdc, usdt) = dex::remove_liquidity(
              &mut storage,
              lp_coin,
              0,
              0,
              ctx(test)
          );

          let pool = dex::borrow_pool<USDC, USDT>(&storage);
          let (usdc_reserves_2, usdt_reserves_2, supply_2) = dex::get_amounts(pool);

          // rounding issues
          assert!(burn(usdt) == 9999999898, 0);
          assert!(burn(usdc) == 9999999, 0);
          assert!(supply_1 == supply_2 + lp_coin_value, 0);
          assert!(usdc_reserves_1 == usdc_reserves_2 + 9999999, 0);
          assert!(usdt_reserves_1 == usdt_reserves_2 + 9999999898, 0);

          test::return_shared(storage);
        }
    }

    #[test]
    fun test_remove_liquidity() {
        let scenario = scenario();
        test_remove_liquidity_(&mut scenario);
        test::end(scenario);
    }

    fun test_add_liquidity_with_fee_(test: &mut Scenario) {
        test_create_pool_(test);

        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;

       let (_, bob) = people();
        
       next_tx(test, bob);
       // Get fees
       {
        let storage = test::take_shared<Storage>(test);

        let (usdc, usdt) = dex::swap(
          &mut storage,
          mint<USDC>(usdc_value, ctx(test)),
          coin::zero<USDT>(ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdc) == 0, 0);
        assert!(burn(usdt) != 0, 0);

        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<USDC, USDT>(&mut storage);

        let root_k = math::sqrt(dex::get_k(usdc_reserves_1, usdt_reserves_1, USDC_DECIMAL_SCALAR, USDT_DECIMAL_SCALAR));
        let root_k_last = math::sqrt(k_last);

        let numerator = supply_1 * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = numerator / denominator;

        let lp_coin = dex::add_liquidity(
          &mut storage,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
        );

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert!(fee > 0, 0);
        assert!(burn(lp_coin) + fee + supply_1 == supply_2, 0);
        
        test::return_shared(storage);
       }
    }

    #[test]
    fun test_add_liquidity_with_fee() {
        let scenario = scenario();
        test_add_liquidity_with_fee_(&mut scenario);
        test::end(scenario);
    }

    fun test_remove_liquidity_with_fee_(test: &mut Scenario) {
        test_create_pool_(test);

       let (_, bob) = people();
        
       next_tx(test, bob);
        {
        let storage = test::take_shared<Storage>(test);

        let (usdc, usdt) = dex::swap(
          &mut storage,
          mint<USDC>(INITIAL_USDC_VALUE / 10, ctx(test)),
          coin::zero<USDT>(ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdc) == 0, 0);
        assert!(burn(usdt) != 0, 0);

        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<USDC, USDT>(&mut storage);

        let root_k = math::sqrt(dex::get_k(usdc_reserves_1, usdt_reserves_1, USDC_DECIMAL_SCALAR, USDT_DECIMAL_SCALAR));
        let root_k_last = math::sqrt(k_last);

        let numerator = supply_1 * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = numerator / denominator;

        let (ether, usdc) = dex::remove_liquidity(
          &mut storage,
          mint<SLPCoin<USDC, USDT>>(30000, ctx(test)),
          0,
          0,
          ctx(test)
        );

        burn(ether);
        burn(usdc);

        let pool = dex::borrow_pool<USDC, USDT>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert!(fee > 0, 0);
        assert!(supply_2 == supply_1 + fee - 30000, 0);

        test::return_shared(storage);
       }
    }

    #[test]
    fun test_remove_liquidity_with_fee() {
        let scenario = scenario();
        test_remove_liquidity_with_fee_(&mut scenario);
        test::end(scenario);
    }

    fun remove_fee(test: &mut Scenario) {
      let (owner, _) = people();
        
       next_tx(test, owner);
       {
        let admin_cap = test::take_from_sender<AdminCap>(test);
        let storage = test::take_shared<Storage>(test);

        dex::update_fee_to(&admin_cap, &mut storage, ZERO_ACCOUNT);

        test::return_shared(storage);
        test::return_to_sender(test, admin_cap)
       }
    }
}