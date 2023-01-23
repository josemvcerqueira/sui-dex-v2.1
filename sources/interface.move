module ipx::interface {
  use std::vector;

  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::pay;

  use ipx::dex_volatile::{Self as volatile, Storage as VStorage, VLPCoin};
  use ipx::dex_stable::{Self as stable, Storage as SStorage, SLPCoin};
  use ipx::utils;

  const ERROR_UNSORTED_COINS: u64 = 1;
  const ERROR_ZERO_VALUE_SWAP: u64 = 2;

  entry public fun create_pool<X, Y>(
      storage: &mut VStorage,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      ctx: &mut TxContext
  ) {
    let coin_x = coin::zero<X>(ctx);
    let coin_y = coin::zero<Y>(ctx);

    pay::join_vec(&mut coin_x, vector_x);
    pay::join_vec(&mut coin_y, vector_y);

    if (utils::are_coins_sorted<X, Y>()) {
      transfer::transfer(
        volatile::create_pool(
          storage,
          coin_x,
          coin_y,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::transfer(
        volatile::create_pool(
          storage,
          coin_y,
          coin_x,
          ctx
        ),
        tx_context::sender(ctx)
      )
    }
  }

  entry public fun swap<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_in_value: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {
    let (coin_x, coin_y) = handle_swap_vectors(vector_x, vector_y, coin_in_value, ctx);

  if (utils::are_coins_sorted<X, Y>()) {
   let (coin_x, coin_y) = swap_<X, Y>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    safe_transfer(coin_x, ctx);
    safe_transfer(coin_y, ctx);
    } else {
    let (coin_y, coin_x) = swap_<Y, X>(
      v_storage,
      s_storage,
      coin_y,
      coin_x,
      coin_out_min_value,
      ctx
    );
    
    safe_transfer(coin_x, ctx);
    safe_transfer(coin_y, ctx);
    }
  }

  entry public fun one_hop_swap<X, Y, Z>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_in_value: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {
    let (coin_x, coin_y) = handle_swap_vectors(vector_x, vector_y, coin_in_value, ctx);

    let (coin_x, coin_y) = one_hop_swap_<X, Y, Z>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    safe_transfer(coin_x, ctx);
    safe_transfer(coin_y, ctx);
  }

  entry public fun two_hop_swap<X, Y, B1, B2>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_in_value: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {
    let (coin_x, coin_y) = handle_swap_vectors(vector_x, vector_y, coin_in_value, ctx);
    let sender = tx_context::sender(ctx);

    // Y -> B1 -> B2 -> X
    if (coin::value(&coin_x) == 0) {

    if (utils::are_coins_sorted<Y, B1>()) {
      let (coin_y, coin_b1) = swap_(
        v_storage,
        s_storage,
        coin_y,
        coin::zero<B1>(ctx),
        0,
        ctx
      );

      let (coin_b1, coin_x) = one_hop_swap_<B1, X, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_x,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_y);
      coin::destroy_zero(coin_b1);
      transfer::transfer(coin_x, sender);
    } else {
      let (coin_b1, coin_y) = swap_(
        v_storage,
        s_storage,
        coin::zero<B1>(ctx),
        coin_y,
        0,
        ctx
      );

      let (coin_b1, coin_x) = one_hop_swap_<B1, X, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_x,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_y);
      coin::destroy_zero(coin_b1);
      transfer::transfer(coin_x, sender);
    }  

    // X -> B1 -> B2 -> Y
    } else {
      if (utils::are_coins_sorted<X, B1>()) {
        let (coin_x, coin_b1) = swap_(
          v_storage,
          s_storage,
          coin_x,
          coin::zero<B1>(ctx),
          0,
          ctx
        );

       let (coin_b1, coin_y) = one_hop_swap_<B1, Y, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_y,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_x);
      coin::destroy_zero(coin_b1);
      transfer::transfer(coin_y, sender);
      } else {
        let (coin_b1, coin_x) = swap_(
          v_storage,
          s_storage,
          coin::zero<B1>(ctx),
          coin_x,
          0,
          ctx
        );

       let (coin_b1, coin_y) = one_hop_swap_<B1, Y, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_y,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_x);
      coin::destroy_zero(coin_b1);
      transfer::transfer(coin_y, sender);
      }
    }
  }

  entry public fun add_liquidity<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    is_volatile: bool,
    vlp_coin_min_amount: u64,
    ctx: &mut TxContext
  ) {
    assert!(utils::are_coins_sorted<X, Y>(), ERROR_UNSORTED_COINS);

    let coin_x = coin::zero<X>(ctx);
    let coin_y = coin::zero<Y>(ctx);

    pay::join_vec(&mut coin_x, vector_x);
    pay::join_vec(&mut coin_y, vector_y);

    let coin_x_value = coin::value(&coin_x);
    let coin_y_value = coin::value(&coin_y);
    let sender = tx_context::sender(ctx);

    let (coin_x_reserves, coin_y_reserves, _) = if (is_volatile) {
        volatile::get_amounts(volatile::borrow_pool<X, Y>(v_storage))
    } else {
        stable::get_amounts(stable::borrow_pool<X, Y>(s_storage))
    };

    let coin_x_optimal_value = (coin_y_value * coin_x_reserves) / coin_y_reserves;

    if (coin_x_value > coin_x_optimal_value) pay::split_and_transfer(&mut coin_x, coin_x_value - coin_x_optimal_value, sender, ctx);

    let coin_y_optimal_value = (coin_x_optimal_value * coin_y_reserves) / coin_x_reserves;

    if (coin_y_value > coin_y_optimal_value) pay::split_and_transfer(&mut coin_y, coin_y_value - coin_y_optimal_value, sender, ctx);

    if (is_volatile) {
      transfer::transfer(
        volatile::add_liquidity(
        v_storage,
        coin_x,
        coin_y,
        vlp_coin_min_amount,
        ctx
      ),
      tx_context::sender(ctx)
    )  
    } else {
      transfer::transfer(
        stable::add_liquidity(
        s_storage,
        coin_x,
        coin_y,
        0,
        ctx
      ),
      tx_context::sender(ctx)
    )  
    }
  }

  entry public fun remove_v_liquidity<X, Y>(
    storage: &mut VStorage,
    vector_lp_coin: vector<Coin<VLPCoin<X, Y>>>,
    coin_amount_in: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    let coin = coin::zero<VLPCoin<X, Y>>(ctx);
    
    pay::join_vec(&mut coin, vector_lp_coin);

    let coin_value = coin::value(&coin);

    let sender = tx_context::sender(ctx);

    if (coin_value > coin_amount_in) pay::split_and_transfer(&mut coin, coin_value - coin_amount_in, sender, ctx);

    let (coin_x, coin_y) = volatile::remove_liquidity(
      storage,
      coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

  entry public fun remove_s_liquidity<X, Y>(
    storage: &mut SStorage,
    vector_lp_coin: vector<Coin<SLPCoin<X, Y>>>,
    coin_amount_in: u64,
    ctx: &mut TxContext
  ){
    let coin = coin::zero<SLPCoin<X, Y>>(ctx);
    
    pay::join_vec(&mut coin, vector_lp_coin);

    let coin_value = coin::value(&coin);

    let sender = tx_context::sender(ctx);

    if (coin_value > coin_amount_in) pay::split_and_transfer(&mut coin, coin_value - coin_amount_in, sender, ctx);

    let (coin_x, coin_y) = stable::remove_liquidity(
      storage,
      coin, 
      0,
      0,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

  public fun swap_<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {

    if (is_volatile_better(v_storage, s_storage, &coin_x, &coin_y)) {
      volatile::swap(
        v_storage,
        coin_x,
        coin_y,
        coin_out_min_value,
        ctx
      ) 
    } else {
      stable::swap(
        s_storage,
        coin_x,
        coin_y,
        coin_out_min_value,
        ctx
      )
    }
  }

  public fun one_hop_swap_<X, Y, Z>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {

        let is_coin_x_value_zero = coin::value(&coin_x) == 0;

        assert!(!is_coin_x_value_zero || coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);

        // Y -> Z -> X
        if (is_coin_x_value_zero) {
           coin::destroy_zero(coin_x);

           if (utils::are_coins_sorted<Y, Z>()) {
            let coin_z = swap_token_x<Y, Z>(
             v_storage,
             s_storage,
             coin_y, 
             0, 
             ctx
            );

            if (utils::are_coins_sorted<X, Z>()) {
            let coin_x = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            (coin_x, coin::zero<Y>(ctx))
            
            } else {
            let coin_x = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
             (coin_x, coin::zero<Y>(ctx))
              }
           } else {
            let coin_z = swap_token_y<Z, Y>(
              v_storage,
              s_storage,
              coin_y, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<X, Z>()) {
            let coin_x = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            (coin_x, coin::zero<Y>(ctx))
            } else {
            let coin_x = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            (coin_x, coin::zero<Y>(ctx))
            }
           }

        // X -> Z -> Y
        } else {
            coin::destroy_zero(coin_y);

           if (utils::are_coins_sorted<X, Z>()) {
            let coin_z = swap_token_x<X, Z>(
              v_storage,
              s_storage,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {
            let coin_y = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            (coin::zero<X>(ctx), coin_y)
            
            } else {
            let coin_y = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
             (coin::zero<X>(ctx), coin_y)
              }
           } else {
            let coin_z = swap_token_y<Z, X>(
              v_storage,
              s_storage,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {
            let coin_y = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            (coin::zero<X>(ctx), coin_y)
            } else {
            let coin_y = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            (coin::zero<X>(ctx), coin_y)
              }
           }
        }
    }

  fun safe_transfer<T>(
    coin: Coin<T>,
    ctx: &mut TxContext
    ) {
      if (coin::value(&coin) == 0) {
        coin::destroy_zero(coin);
      } else {
        transfer::transfer(coin, tx_context::sender(ctx));
      };
    }

  fun handle_swap_vectors<X, Y>(
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_in_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {
    let coin_x = coin::zero<X>(ctx);
    let coin_y = coin::zero<Y>(ctx);
    let sender = tx_context::sender(ctx);

    if (vector::is_empty(&vector_y)) {
      pay::join_vec(&mut coin_x, vector_x);
      vector::destroy_empty(vector_y);

      let coin_x_value = coin::value(&coin_x);
      if (coin_x_value > coin_in_value) pay::split_and_transfer(&mut coin_x, coin_x_value - coin_in_value, sender, ctx);
    } else {
      pay::join_vec(&mut coin_y, vector_y);
      vector::destroy_empty(vector_x);

      let coin_y_value = coin::value(&coin_y);
      if (coin_y_value > coin_in_value) pay::split_and_transfer(&mut coin_y, coin_y_value - coin_in_value, sender, ctx);
    };

    (coin_x, coin_y)
  }

  fun swap_token_x<X, Y>(
      v_storage: &mut VStorage,
      s_storage: &mut SStorage,
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
      let coin_y = coin::zero<Y>(ctx);
      let is_volatile_better = is_volatile_better(v_storage, s_storage, &coin_x, &coin_y);

      coin::destroy_zero(coin_y);

      if (is_volatile_better) {
        volatile::swap_token_x(v_storage, coin_x, coin_y_min_value, ctx)
        } else {
        stable::swap_token_x(s_storage, coin_x, coin_y_min_value, ctx)
        }
    }

  fun swap_token_y<X, Y>(
      v_storage: &mut VStorage,
      s_storage: &mut SStorage,
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        let coin_x = coin::zero<X>(ctx);
        let is_volatile_better = is_volatile_better(v_storage, s_storage, &coin_x, &coin_y);

        coin::destroy_zero(coin_x);

        if (is_volatile_better) {
          volatile::swap_token_y(v_storage, coin_y, coin_x_min_value, ctx)
          } else {
          stable::swap_token_y(s_storage, coin_y, coin_x_min_value, ctx)
          }
    }  

  fun is_volatile_better<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: &Coin<X>,
    coin_y: &Coin<Y>
  ): bool {

    if (!stable::is_pool_deployed<X, Y>(s_storage)) return true;

    let v_pool = volatile::borrow_pool<X, Y>(v_storage);
    let s_pool = stable::borrow_pool<X, Y>(s_storage);

    let (v_reserve_x, v_reserve_y, _) = volatile::get_amounts(v_pool);
    let (s_reserve_x, s_reserve_y, _) = stable::get_amounts(s_pool);

    let coin_x_value = coin::value(coin_x);

    let v_amount_out = if (coin_x_value == 0) {
      volatile::calculate_value_out(coin::value(coin_y), v_reserve_y, v_reserve_x)
    } else {
      volatile::calculate_value_out(coin::value(coin_x), v_reserve_x, v_reserve_y)
    };

    let s_amount_out = if (coin_x_value == 0) {
      stable::calculate_value_out(s_pool, coin::value(coin_y), s_reserve_x, s_reserve_y, false)
    } else {
      stable::calculate_value_out(s_pool, coin::value(coin_x), s_reserve_x, s_reserve_y, true)
    };

    v_amount_out >= s_amount_out
  }
}