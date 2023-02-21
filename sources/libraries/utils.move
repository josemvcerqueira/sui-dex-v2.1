module ipx::utils {
  use std::type_name::{Self};
  use std::ascii::{String};
  use std::ascii;
  use std::vector;

  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::pay;
  use sui::transfer;

  use ipx::comparator;

    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

    const ERROR_SAME_COIN: u64 = 1;
    const ERROR_UNSORTED_COINS: u64 = 2;

    public fun get_smaller_enum(): u8 {
        SMALLER
    }

    public fun get_greater_enum(): u8 {
        GREATER
    }

    public fun get_equal_enum(): u8 {
        EQUAL
    }

    public fun get_coin_info<T>(): vector<u8> {
       let name = type_name::into_string(type_name::get<T>());
       ascii::into_bytes(name)
    }

    public fun get_coin_info_string<T>(): String {
      type_name::into_string(type_name::get<T>())
    }

    fun compare_struct<X,Y>(): u8 {
        let struct_x_bytes: vector<u8> = get_coin_info<X>();
        let struct_y_bytes: vector<u8> = get_coin_info<Y>();
        if (comparator::is_greater_than(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            GREATER
        } else if (comparator::is_equal(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            EQUAL
        } else {
            SMALLER
        }
    }

    public fun are_coins_sorted<X,Y>(): bool {
        let compare_x_y: u8 = compare_struct<X, Y>();
        assert!(compare_x_y != get_equal_enum(), ERROR_SAME_COIN);
        (compare_x_y == get_smaller_enum())
    }

  public  fun handle_coin_vector<X>(
      vector_x: vector<Coin<X>>,
      coin_in_value: u64,
      ctx: &mut TxContext
    ): Coin<X> {
      let coin_x = coin::zero<X>(ctx);

      if (vector::is_empty(&vector_x)){
        vector::destroy_empty(vector_x);
        return coin_x
      };

      pay::join_vec(&mut coin_x, vector_x);

      let coin_x_value = coin::value(&coin_x);
      if (coin_x_value > coin_in_value) pay::split_and_transfer(&mut coin_x, coin_x_value - coin_in_value, tx_context::sender(ctx), ctx);

      coin_x
    }

   public fun destroy_zero_or_transfer<T>(
      coin: Coin<T>,
      ctx: &mut TxContext
      ) {
        if (coin::value(&coin) == 0) {
          coin::destroy_zero(coin);
        } else {
          transfer::transfer(coin, tx_context::sender(ctx));
        };
    }

    public fun quote_liquidity(amount_a: u64, reserves_a: u64, reserves_b: u64): u64 {
      amount_a * reserves_b / reserves_a
    }
}