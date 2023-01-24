module ipx::dex_stable {

  use std::string::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Supply, Balance};
  use sui::object::{Self,UID, ID};
  use sui::transfer;
  use sui::math;
  use sui::bag::{Self, Bag};
  use sui::event;

  use ipx::utils;
  use ipx::u256::{Self, U256};

  const DEV: address = @dev;
  const ZERO_ACCOUNT: address = @zero;
  const MAX_POOL_COIN_AMOUNT: u64 = {
        18446744073709551615 / 10000
    };
  const MINIMUM_LIQUIDITY: u64 = 10;
  const PRECISION: u64 = 100000;
  const FEE_PERCENT: u64 = 50; // 0.05%
  const K_PRECISION: u64 = 1000000000; //1e9

  const ERROR_CREATE_PAIR_ZERO_VALUE: u64 = 1;
  const ERROR_POOL_IS_FULL: u64 = 2;
  const ERROR_POOL_EXISTS: u64 = 3;
  const ERROR_ZERO_VALUE_SWAP: u64 = 4;
  const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
  const ERROR_SLIPPAGE: u64 = 6;
  const ERROR_ADD_LIQUIDITY_ZERO_AMOUNT: u64 = 7;
  const ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT: u64 = 8;
  const ERROR_REMOVE_LIQUIDITY_X_AMOUNT: u64 = 9;
  const ERROR_REMOVE_LIQUIDITY_Y_AMOUNT: u64 = 10;

    struct AdminCap has key {
      id: UID,
    }

    struct Storage has key {
      id: UID,
      pools: Bag,
      fee_to: address
    }

    struct SLPCoin<phantom X, phantom Y> has drop {}

    struct SPool<phantom X, phantom Y> has key, store {
        id: UID,
        k_last: u64,
        lp_coin_supply: Supply<SLPCoin<X, Y>>,
        balance_x: Balance<X>,
        balance_y: Balance<Y>,
        decimals_x: u64,
        decimals_y: u64
    }

    // Events
    struct PoolCreated<phantom P> has copy, drop {
      id: ID,
      shares: u64,
      value_x: u64,
      value_y: u64,
      sender: address
    }

    struct SwapTokenX<phantom X, phantom Y> has copy, drop {
      id: ID,
      sender: address,
      coin_x_in: u64,
      coin_y_out: u64
    }

    struct SwapTokenY<phantom X, phantom Y> has copy, drop {
      id: ID,
      sender: address,
      coin_y_in: u64,
      coin_x_out: u64
    }

    struct AddLiquidity<phantom P> has copy, drop {
      id: ID,
      sender: address,
      coin_x_amount: u64,
      coin_y_amount: u64,
      shares_minted: u64
    }

    struct RemoveLiquidity<phantom P> has copy, drop {
      id: ID,
      sender: address,
      coin_x_out: u64,
      coin_y_out: u64,
      shares_destroyed: u64
    } 

    /**
    * @dev It gives the caller the AdminCap object. The AdminCap allows the holder to update the fee_to key. 
    * It shares the Storage object with the Sui Network.
    */
    fun init(ctx: &mut TxContext) {
      // Give administrator capabilities to the deployer
      // He has the ability to update the fee_to key on the Storage
      transfer::transfer(
        AdminCap { 
          id: object::new(ctx)
        }, 
        tx_context::sender(ctx)
        );

      // Share the Storage object
      transfer::share_object(
         Storage {
           id: object::new(ctx),
           pools: bag::new(ctx),
           fee_to: DEV
         }
      );
    }

    /**
    * @notice The zero address receives a small amount of shares to prevent zero divisions in the future. 
    * @notice Please make sure that the tokens X and Y are sorted before calling this fn.
    * @dev It creates a new Pool with X and Y coins. The pool accepts swaps using the x3y+y3x >= k invariant.
    * @param storage the object that stores the pools Bag
    * @oaram coin_x the first token of the pool
    * @param coin_y the scond token of the pool
    * @return The number of shares as VLPCoins that can be used later on to redeem his coins + commissions.
    * Requirements: 
    * - It will throw if the X and Y are not sorted.
    * - Both coins must have a value greater than 0. 
    * - The pool has a maximum capacity to prevent overflows.
    * - There can only be one pool per each token pair, regardless of their order.
    */
    public fun create_pool<X, Y>(
      _: &AdminCap,
      storage: &mut Storage,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      decimals_x: u8,
      decimals_y: u8,      ctx: &mut TxContext
    ): Coin<SLPCoin<X, Y>> {
      // Store the value of the coins locally
      let coin_x_value = coin::value(&coin_x);
      let coin_y_value = coin::value(&coin_y);

      // Ensure that the both coins have a value greater than 0.
      assert!(coin_x_value != 0 && coin_y_value != 0, ERROR_CREATE_PAIR_ZERO_VALUE);    
      // Make sure the value does not exceed the maximum amount to prevent overflows.    
      assert!(MAX_POOL_COIN_AMOUNT > coin_x_value && MAX_POOL_COIN_AMOUNT > coin_y_value, ERROR_POOL_IS_FULL);

      // Construct the name of the VLPCoin, which will be used as a key to store the pool data.
      // This fn will throw if X and Y are not sorted.
      let lp_coin_name = utils::get_lp_coin_name<X, Y>();

      // Checks that the pool does not exist.
      assert!(!bag::contains(&storage.pools, lp_coin_name), ERROR_POOL_EXISTS);

      // Calculate the scalar of the decimals.
      let decimals_x = math::pow(10, decimals_x);
      let decimals_y = math::pow(10, decimals_y);

      // Calculate k = x3y+y3x
      let k = k(coin_x_value, coin_y_value, decimals_x, decimals_y);
      // Calculate the number of shares
      let shares = math::sqrt(k);

      // Create the SLP coin for the Pool<X, Y>. 
      // This coin has 0 decimals and no metadata 
      let supply = balance::create_supply(SLPCoin<X, Y> {});
      let min_liquidity_balance = balance::increase_supply(&mut supply, MINIMUM_LIQUIDITY);
      let sender_balance = balance::increase_supply(&mut supply, shares);

      // Transfer the zero address shares
      transfer::transfer(coin::from_balance(min_liquidity_balance, ctx), ZERO_ACCOUNT);

      // Calculate an id for the pool and the event
      let id = object::new(ctx);

      event::emit(
          PoolCreated<SPool<X, Y>> {
            id: object::uid_to_inner(&id),
            shares,
            value_x: coin_x_value,
            value_y: coin_y_value,
            sender: tx_context::sender(ctx)
          }
        );

      // Store the new pool in Storage.pools
      bag::add(
        &mut storage.pools,
        lp_coin_name,
        SPool {
          id,
          k_last: k,
          lp_coin_supply: supply,
          balance_x: coin::into_balance<X>(coin_x),
          balance_y: coin::into_balance<Y>(coin_y),
          decimals_x,
          decimals_y,
          }
        );

      // Return the caller shares
      coin::from_balance(sender_balance, ctx)
    }

    /**
    * @dev This fn performs a swap between X and Y coins on a Pool<X, Y>. 
    * Only one of the coins must have a value of 0 or the fn will throw. 
    * It is a helper fn build on top of `swap_token_x` and `swap_token_y`. To save gas a caller can call the underlying fns.
    * If X is 0, the fn will swap Y -> X and vice versa.
    * @param storage the object that stores the pools Bag
    * @oaram coin_x If this coin has a value greater than 0, it will be swapped for Y
    * @param coin_y If this coin has a value greater than 0, it will be swapped for X
    * @param coin_out_min_value The minimum value the caller wishes to receive after the swap.
    * @return A tuple of both coins. One of the coins will be zero, the one that the caller intended to sell, and the other will have a value.
    * Requirements: 
    * - Coins X and Y must be sorted.
    * - One of the coins must have a value of 0 and the other a value greater than 0 
    */
    public fun swap<X, Y>(
      storage: &mut Storage,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      coin_out_min_value: u64,
      ctx: &mut TxContext
      ): (Coin<X>, Coin<Y>) {
       let is_coin_x_value_zero = coin::value(&coin_x) == 0;

        // Make sure one of the coins has a value of 0 and the other does not.
        assert!(!is_coin_x_value_zero || coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);

        // If Coin<X> has a value of 0, we will swap Y -> X
        if (is_coin_x_value_zero) {
          coin::destroy_zero(coin_x);
          let coin_x = swap_token_y(storage, coin_y, coin_out_min_value, ctx);
           (coin_x, coin::zero<Y>(ctx)) 
        } else {
          // If Coin<Y> has a value of 0, we will swap X -> Y
          coin::destroy_zero(coin_y);
          let coin_y = swap_token_x(storage, coin_x, coin_out_min_value, ctx);
          (coin::zero<X>(ctx), coin_y) 
        }
      }

    /**
    * @dev This fn allows the caller to deposit coins X and Y on the Pool<X, Y>.
    * This function will not throw if one of the coins has a value of 0, but the caller will get shares (SLPCoin) with a value of 0.
    * @param storage the object that stores the pools Bag 
    * @param coin_x The Coin<X> the user wishes to deposit on Pool<X, Y>
    * @param coin_y The Coin<Y> the user wishes to deposit on Pool<X, Y>
    * @param vlp_coin_min_amount the minimum amount of shares to receive. It prevents high slippage from frontrunning. 
    * @return VLPCoin with a value in proportion to the Coin deposited and the reserves of the Pool<X, Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun add_liquidity<X, Y>(   
      storage: &mut Storage,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      slp_coin_min_amount: u64,
      ctx: &mut TxContext
      ): Coin<SLPCoin<X, Y>> {
        // Save the value of the coins locally.
        let coin_x_value = coin::value(&coin_x);
        let coin_y_value = coin::value(&coin_y);
        
        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Mint the fee amount if `fee_to` is not the @0x0. 
        // The fee amount is equivalent to 1/5 of all commissions collected. 
        // If the fee is on, we need to save the K in the k_last key to calculate the next fee amount. 
        let is_fee_on = mint_fee(pool, fee_to, ctx);

        // Make sure that both coins havea value greater than 0 to save gas for the user.
        assert!(coin_x_value != 0 && coin_x_value != 0, ERROR_ADD_LIQUIDITY_ZERO_AMOUNT);

        // Save the reserves and supply amount of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, supply) = get_amounts(pool);

        // Calculate the number of shares to mint. Note if of the coins has a value of 0. The `shares_to_mint` will be 0.
        let share_to_mint = math::min(
          (coin_x_value * supply) / coin_x_reserve,
          (coin_y_value * supply) / coin_y_reserve
        );

        // Make sure the user receives the minimum amount desired or higher.
        assert!(share_to_mint >= slp_coin_min_amount, ERROR_SLIPPAGE);

        // Deposit the coins in the Pool<X, Y>.
        let new_reserve_x = balance::join(&mut pool.balance_x, coin::into_balance(coin_x));
        let new_reserve_y = balance::join(&mut pool.balance_y, coin::into_balance(coin_y));

        // Make sure that the pool is not full.
        assert!(MAX_POOL_COIN_AMOUNT >= new_reserve_x, ERROR_POOL_IS_FULL);
        assert!(MAX_POOL_COIN_AMOUNT >= new_reserve_y, ERROR_POOL_IS_FULL);

        // Emit the AddLiquidity event
        event::emit(
          AddLiquidity<SPool<X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_amount: coin_x_value, 
          coin_y_amount: coin_y_value,
          shares_minted: share_to_mint
          }
        );

        // If the fee mechanism is turned on, we need to save the K for the next calculation.
        if (is_fee_on) pool.k_last = k(new_reserve_x, new_reserve_y, pool.decimals_x, pool.decimals_y);

        // Return the shares(VLPCoin) to the caller.
        coin::from_balance(balance::increase_supply(&mut pool.lp_coin_supply, share_to_mint), ctx)
      }

    /**
    * @dev It allows the caller to redeem his underlying coins in proportions to the SLPCoins he burns. 
    * @param storage the object that stores the pools Bag 
    * @param lp_coin the shares to burn
    * @param coin_x_min_amount the minimum value of Coin<X> the caller wishes to receive.
    * @param coin_y_min_amount the minimum value of Coin<Y> the caller wishes to receive.
    * @return A tuple with Coin<X> and Coin<Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun remove_liquidity<X, Y>(   
      storage: &mut Storage,
      lp_coin: Coin<SLPCoin<X, Y>>,
      coin_x_min_amount: u64,
      coin_y_min_amount: u64,
      ctx: &mut TxContext
      ): (Coin<X>, Coin<Y>) {
        // Store the value of the shares locally
        let lp_coin_value = coin::value(&lp_coin);

        // Throw if the lp_coin has a value of 0 to save gas.
        assert!(lp_coin_value != 0, ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT);

        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Mint the fee amount if `fee_to` is not the @0x0. 
        // The fee amount is equivalent to 1/5 of all commissions collected. 
        // If the fee is on, we need to save the K in the k_last key to calculate the next fee amount. 
        let is_fee_on = mint_fee(pool, fee_to, ctx);

        // Save the reserves and supply amount of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, lp_coin_supply) = get_amounts(pool);

        // Calculate the amount of coins to receive in proportion of the `lp_coin_value`. 
        // It maintains the K = x * y of the Pool<X, Y>
        let coin_x_removed = (lp_coin_value * coin_x_reserve) / lp_coin_supply;
        let coin_y_removed = (lp_coin_value * coin_y_reserve) / lp_coin_supply;
        
        // Make sure that the caller receives the minimum amount desired.
        assert!(coin_x_removed >= coin_x_min_amount, ERROR_REMOVE_LIQUIDITY_X_AMOUNT);
        assert!(coin_y_removed >= coin_y_min_amount, ERROR_REMOVE_LIQUIDITY_Y_AMOUNT);

        // Burn the VLPCoin deposited
        balance::decrease_supply(&mut pool.lp_coin_supply, coin::into_balance(lp_coin));

        // Emit the RemoveLiquidity event
        event::emit(
          RemoveLiquidity<SPool<X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_out: coin_x_removed,
          coin_y_out: coin_y_removed,
          shares_destroyed: lp_coin_value
          }
        );

        // Store the current K for the next fee calculation.
        if (is_fee_on) pool.k_last = k((coin_x_reserve - coin_x_removed), (coin_y_reserve - coin_y_removed), pool.decimals_x, pool.decimals_y);

        // Remove the coins from the Pool<X, Y> and return to the caller.
        (
          coin::take(&mut pool.balance_x, coin_x_removed, ctx),
          coin::take(&mut pool.balance_y, coin_y_removed, ctx),
        )
      }


    /**
    * @dev It returns an immutable Pool<X, Y>. 
    * @param storage the object that stores the pools Bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun borrow_pool<X, Y>(storage: &Storage): &SPool<X, Y> {
      bag::borrow<String, SPool<X, Y>>(&storage.pools, utils::get_lp_coin_name<X, Y>())
    }

    /**
    * @dev It indicates to the caller if Pool<X, Y> has been deployed. 
    * @param storage the object that stores the pools Bag 
    * @return bool True if the pool has been deployed.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun is_pool_deployed<X, Y>(storage: &Storage):bool {
      bag::contains(&storage.pools, utils::get_lp_coin_name<X, Y>())
    }

    /**
    * @param pool an immutable Pool<X, Y>
    * @return It returns a triple of Tuple<coin_x_reserves, coin_y_reserves, lp_coin_supply>. 
    */
    public fun get_amounts<X, Y>(pool: &SPool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.balance_x),
            balance::value(&pool.balance_y),
            balance::supply_value(&pool.lp_coin_supply)
        )
    }

    /**
    * @dev A helper fn to calculate the value of tokenA in tokenB in a Pool<A, B>. This function remove the commission of 0.05% from the `coin_in_amount`.
    * Algo logic taken from Andre Cronje's Solidly
    * @param coin_amount the amount being sold
    * @param balance_x the reserves of the Coin<X> in a Pool<A, B>. 
    * @param balance_y The reserves of the Coin<Y> in a Pool<A, B>. 
    * @param is_x it indicates if the `coin_amount` is Coin<X> or Coin<Y>.
    * @return the value of A in terms of B.
    */
  public fun calculate_value_out<X, Y>(
      pool: &SPool<X, Y>,
      coin_amount: u64,
      balance_x: u64,
      balance_y:u64,
      is_x: bool
    ): u64 {
        // Precision is used to scale the number for more precise calculations. 
        // We convert them to u256 for more precise calculations and to avoid overflows.
        let token_in_u256 = u256::from_u64(coin_amount);

        // We calculate the amount being sold after the fee. 
        let token_in_amount_minus_fees_adjusted = u256::sub(token_in_u256, 
          u256::div(
          u256::mul(token_in_u256, u256::from_u64(FEE_PERCENT)),
          u256::from_u64(PRECISION))
        );

        let _k = u256::from_u64(k(balance_x, balance_y, pool.decimals_x, pool.decimals_y));  

        let k_precision = u256::from_u64(K_PRECISION);
        let balance_x = u256::from_u64(balance_x);
        let balance_y = u256::from_u64(balance_y);
        let decimals_x = u256::from_u64(pool.decimals_x);
        let decimals_y = u256::from_u64(pool.decimals_y);

        // Calculate the stable curve invariant k = x3y+y3x 
        // We need to consider stable coins with different decimal values
        let reserve_x = u256::div(u256::mul(balance_x, k_precision), decimals_x); 
        let reserve_y = u256::div(u256::mul(balance_y, k_precision), decimals_y); 

        let amount_in = if (is_x) 
          { u256::div(u256::mul(token_in_amount_minus_fees_adjusted, k_precision), decimals_x) } 
          else 
          { u256::div(u256::mul(token_in_amount_minus_fees_adjusted, k_precision), decimals_y) };


        let y = if (is_x) 
          { u256::sub(reserve_y, y(u256::add(amount_in, reserve_x), _k, reserve_y, k_precision)) } 
          else 
          { u256::sub(reserve_x, y(u256::add(amount_in, reserve_y), _k, reserve_x, k_precision)) };
        u256::as_u64(u256::div(u256::mul(y, if (is_x) { decimals_y } else { decimals_x } ), k_precision))  
    }             

   /**
   * @dev It sells the Coin<X> in a Pool<X, Y> for Coin<Y>. 
   * @param storage the object that stores the pools Bag 
   * @param coin_x Coin<X> being sold. 
   * @param coin_y_min_value the minimum value of Coin<Y> the caller will accept.
   * @return Coin<Y> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
   public fun swap_token_x<X, Y>(
      storage: &mut Storage, 
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
        // Ensure we are selling something
        assert!(coin::value(&coin_x) != 0, ERROR_ZERO_VALUE_SWAP);

        // Conver the coin being sold in balance.
        let coin_x_balance = coin::into_balance(coin_x);

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        // Store the value being sold locally
        let coin_x_value = balance::value(&coin_x_balance);
        
        // Calculte how much value of Coin<Y> the caller will receive.
        let coin_y_value = calculate_value_out(pool, coin_x_value, coin_x_reserve, coin_y_reserve, true);

        // Make sure the caller receives more than the minimum amount. 
        assert!(coin_y_value >=  coin_y_min_value, ERROR_SLIPPAGE);
        // Makes sure the Pool<X, Y> has enough reserves to cover the swap.
        assert!(coin_y_reserve > coin_y_value, ERROR_NOT_ENOUGH_LIQUIDITY);

        // Emit the SwapTokenX event
        event::emit(
          SwapTokenX<X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_x_in: coin_x_value, 
            coin_y_out: coin_y_value 
            }
          );

        // Add Balance<X> to the Pool<X, Y> 
        balance::join(&mut pool.balance_x, coin_x_balance);
        // Remove the value being bought and give to the caller in Coin<Y>.
        coin::take(&mut pool.balance_y, coin_y_value, ctx)
      }

  /**
   * @dev It sells the Coin<Y> in a Pool<X, Y> for Coin<X>. 
   * @param storage the object that stores the pools Bag 
   * @param coin_y Coin<Y> being sold. 
   * @param coin_x_min_value the minimum value of Coin<X> the caller will accept.
   * @return Coin<X> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
    public fun swap_token_y<X, Y>(
      storage: &mut Storage, 
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        // Ensure we are selling something
        assert!(coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);

        // Convert the coin being sold in balance.
        let coin_y_balance = coin::into_balance(coin_y);

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        // Store the value being sold locally
        let coin_y_value = balance::value(&coin_y_balance);

        // Calculte how much value of Coin<X> the caller will receive.
        let coin_x_value = calculate_value_out(pool, coin_y_value, coin_x_reserve, coin_y_reserve, false);

        assert!(coin_x_value >=  coin_x_min_value, ERROR_SLIPPAGE);
        // Makes sure the Pool<X, Y> has enough reserves to cover the swap.
        assert!(coin_x_reserve > coin_x_value, ERROR_NOT_ENOUGH_LIQUIDITY);

        event::emit(
          SwapTokenY<X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_y_in: coin_y_value, 
            coin_x_out: coin_x_value 
            }
          );

        // Add Balance<Y> to the Pool<X, Y> 
        balance::join(&mut pool.balance_y, coin_y_balance);
        // Remove the value being bought and give to the caller in Coin<X>.
        coin::take(&mut pool.balance_x, coin_x_value, ctx)
      }

    /**
    * @dev It returns a mutable Pool<X, Y>. 
    * @param storage the object that stores the pools Bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    fun borrow_mut_pool<X, Y>(storage: &mut Storage): &mut SPool<X, Y> {
        bag::borrow_mut<String, SPool<X, Y>>(&mut storage.pools, utils::get_lp_coin_name<X, Y>())
      }   

    /**
    * @dev It mints a commission to the `fee_to` address. It collects 20% of the commissions.
    * We collect the fee by minting more shares.
    * @param pool mutable Pool<X, Y>
    * @param fee_to the address that will receive the fee. 
    * @return bool it indicates if a fee was collected or not.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    fun mint_fee<X, Y>(pool: &mut SPool<X, Y>, fee_to: address, ctx: &mut TxContext): bool {
        // If the `fee_to` is the zero address @0x0, we do not collect any protocol fees.
        let is_fee_on = fee_to != ZERO_ACCOUNT;

          if (is_fee_on) {
            // We need to know the last K to calculate how many fees were collected
            if (pool.k_last != 0) {
              // Find the sqrt of the current K
              let root_k = math::sqrt(k(balance::value(&pool.balance_x), balance::value(&pool.balance_y), pool.decimals_x, pool.decimals_y));
              // Find the sqrt of the previous K
              let root_k_last = math::sqrt(pool.k_last);

              // If the current K is higher, trading fees were collected. It is the only way to increase the K. 
              if (root_k > root_k_last) {
                // Number of fees collected in shares
                let numerator = balance::supply_value(&pool.lp_coin_supply) * (root_k - root_k_last);
                // logic to collect 1/5
                let denominator = (root_k * 5) + root_k_last;
                let liquidity = numerator / denominator;
                if (liquidity != 0) {
                  // Increase the shares supply and transfer to the `fee_to` address.
                  let new_balance = balance::increase_supply(&mut pool.lp_coin_supply, liquidity);
                  let new_coins = coin::from_balance(new_balance, ctx);
                  transfer::transfer(new_coins, fee_to);
                }
              }
            };
          // If the protocol fees are off and we have k_last value, we remove it.  
          } else if (pool.k_last != 0) {
            pool.k_last = 0;
          };

       is_fee_on
    }

    fun k(
      x: u64, 
      y: u64,
      decimals_x: u64,
      decimals_y: u64
    ): u64 {
      let x = u256::from_u64(x);
      let y = u256::from_u64(y);
      let precision = u256::from_u64(K_PRECISION);

      let _x = u256::div(u256::mul(x, precision), u256::from_u64(decimals_x));  
      let _y = u256::div(u256::mul(y, precision), u256::from_u64(decimals_y));
      let _a = u256::div(u256::mul(_x, _y), precision);
      let _b = u256::add(u256::div(u256::mul(_x, _x), precision), u256::div(u256::mul(_y, _y), precision));
      u256::as_u64(u256::div(u256::mul(_a, _b), precision)) // x3y+y3x >= k
    }

    fun y(
     x0: U256,
     xy: U256,
     y: U256,
     precision: U256 
    ): U256 {
      let i = 0;

      let one = u256::from_u64(1);

      while (i < 255) {
        i = i + 1;

         let y_prev = y;
         let k = f(x0, y, precision);
            if (u256::compare(&k , &xy) == u256::get_less_than()) {
                let dy = u256::div(u256::mul(u256::sub(xy, k), precision), d(x0, y, precision));
                y = u256::add(y, dy);
            } else {
                let dy = u256::div(u256::mul(u256::sub(k, xy), precision), d(x0, y, precision));
                y = u256::sub(y, dy);
            };
            if (u256::compare(&y, &y_prev) == u256::get_greater_than()) {
              let diff = u256::sub(y, y_prev);
              let pred = u256::compare(&diff, &one);
                if (pred == u256::get_less_than() || pred == u256::get_equal()) {
                    break
                }
            } else {
              let diff = u256::sub(y_prev, y);
              let pred = u256::compare(&diff, &one);
                if (pred == u256::get_less_than() || pred == u256::get_equal()) {
                    break
                }
            }
      };
      y
    }

    fun f(x0: U256, y: U256, precision: U256): U256 {
      u256::add(u256::div(u256::mul(x0, u256::div(u256::mul(u256::div(u256::mul(y, y), precision), y), precision)), precision),
        u256::div(u256::mul(u256::div(u256::mul(u256::div(u256::mul(x0, x0), precision), x0), precision), y), precision)
        )
    }

    fun d(x0: U256, y: U256, precision: U256): U256 {
     u256::add(u256::div(u256::mul(u256::from_u64(3),u256::mul(x0,u256::div(u256::mul(y, y), precision))), precision), 
      u256::div(u256::mul(u256::div(u256::mul(x0, x0), precision), x0), precision)
      )
    }

    /**
    * @dev Admin only fn to update the fee_to. 
    * @param _ the AdminCap 
    * @param storage the object that stores the pools Bag 
    * @param new_fee_to the new `fee_to`.
    */
    entry public fun update_fee_to(
      _:&AdminCap, 
      storage: &mut Storage,
      new_fee_to: address
       ) {
      storage.fee_to = new_fee_to;
    }


    /**
    * @dev Admin only fn to transfer the ownership. 
    * @param admin_cap the AdminCap 
    * @param new_admin the new admin.
    */
    entry public fun transfer_admin_cap(
      admin_cap: AdminCap,
      new_admin: address
    ) {
      transfer::transfer(admin_cap, new_admin);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun get_fee_to(storage: &Storage,): address {
      storage.fee_to
    }

    #[test_only]
    public fun get_k_last<X, Y>(storage: &Storage): u64 {
      let pool = borrow_pool<X, Y>(storage);
      pool.k_last
    }

    #[test_only]
    public fun get_pool_metadata<X, Y>(storage: &Storage): (u64, u64) {
      let pool = borrow_pool<X, Y>(storage);
      (pool.decimals_x, pool.decimals_y)
    }

    #[test_only]
    public fun get_k(
      x: u64, 
      y: u64,
      decimals_x: u64,
      decimals_y: u64
    ): u64 {
      k(x, y, decimals_x, decimals_y)
    }
}