module ipx::ipx {
  use std::option;

  use sui::object::{Self,UID};
  use sui::tx_context::{Self, TxContext};
  use sui::balance::{Self, Supply, Balance};
  use sui::bag::{Self, Bag};
  use sui::table::{Self, Table};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::event;

  use ipx::utils::{get_coin_info};
  use ipx::math::{scalar};

  struct IPX has drop {}

  const IPX_PER_EPOCH: u64 = 100000000000; // 100e9 IPX

  const ERROR_POOL_ADDED_ALREADY: u64 = 1;
  const ERROR_ACCOUNT_BAG_ADDED_ALREADY: u64 = 2;
  const ERROR_NOT_ENOUGH_BALANCE: u64 = 3;

  struct IPXStorage has key {
    id: UID,
    supply: Supply<IPX>,
    ipx_per_epoch: u64,
    total_allocation_points: u64,
    pool_keys: Table<vector<u8>, PoolKey>,
    pools: Table<u64, Pool>,
    start_epoch: u64
  }

  struct Pool has key, store {
    id: UID,
    allocation_points: u64,
    last_reward_epoch: u64,
    accrued_ipx_per_share: u256,
    balance_value: u64
  }

  struct AccountStorage has key {
    id: UID,
    accounts: Table<u64, Bag>
  }

  struct Account<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    rewards_paid: u256
  }

  struct PoolKey has key, store {
    id: UID,
    key: u64
  }

  struct IPXAdmin has key {
    id: UID
  }

  // Events

  struct SetAllocationPoints<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct AddPool<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct Stake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct Unstake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }


  struct NewAdmin has drop, copy {
    admin: address
  }

  fun init(ctx: &mut TxContext, start_epoch: u64) {
      let (treasury, metadata) = coin::create_currency(
            IPX {}, 
            9,
            b"IPX",
            b"Interest Protocol Token",
            b"The governance token of Interest Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")),
            ctx
        );

      let pools = table::new<u64, Pool>(ctx);  
      let pool_keys = table::new<vector<u8>, PoolKey>(ctx);
      let accounts = table::new<u64, Bag>(ctx);
      
      table::add(
        &mut pool_keys, 
        get_coin_info<IPX>(), 
        PoolKey { 
          id: object::new(ctx), 
          key: 0,
          }
        );

      table::add(
        &mut pools, 
        0, // Key is the length of the bag before a new element is added 
        Pool {
          id: object::new(ctx),
          allocation_points: 1000,
          last_reward_epoch: tx_context::epoch(ctx),
          accrued_ipx_per_share: 0,
          balance_value: 0
        }
      );

      
      transfer::freeze_object(metadata);
      transfer::share_object(
        IPXStorage {
          id: object::new(ctx),
          supply: coin::treasury_into_supply(treasury),
          pools,
          ipx_per_epoch: IPX_PER_EPOCH,
          total_allocation_points: 0,
          pool_keys,
          start_epoch
        }
      );

      transfer::share_object(
        AccountStorage {
          id: object::new(ctx),
          accounts
        }
      );

      transfer::transfer(IPXAdmin { id: object::new(ctx) }, tx_context::sender(ctx));
  }

 public fun get_pending_rewards<T>(
  storage: &IPXStorage,
  accounts_storage: &AccountStorage,
  ctx: &mut TxContext
  ): u256 {

    if ((!bag::contains<address>(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), tx_context::sender(ctx)))) return 0;

    let pool = borrow_pool<T>(storage);
    let account = borrow_account<T>(storage, accounts_storage, tx_context::sender(ctx));

    let total_balance = (pool.balance_value as u256);
    let account_balance_value = (balance::value(&account.balance) as u256);

    if (total_balance == 0 || account_balance_value == 0) return 0;

    let current_epoch = tx_context::epoch(ctx);
    let accrued_ipx_per_share = pool.accrued_ipx_per_share;

    if (current_epoch > pool.last_reward_epoch) {
      let epochs_delta = ((current_epoch - pool.last_reward_epoch) as u256);
      let rewards = (epochs_delta * (storage.ipx_per_epoch as u256)) * (pool.allocation_points as u256) / (storage.total_allocation_points as u256);
      accrued_ipx_per_share = accrued_ipx_per_share + (rewards * scalar() / (pool.balance_value as u256));
    };

    return (account_balance_value * accrued_ipx_per_share) - account.rewards_paid
  }

 public fun stake<T>(
  storage: &mut IPXStorage, 
  accounts_storage: &mut AccountStorage,
  token: Coin<T>,
  ctx: &mut TxContext
 ): Coin<IPX> {
  update_pool<T>(storage, ctx);
  let sender = tx_context::sender(ctx);

   if (!bag::contains<address>(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)) {
    bag::add(
      table::borrow_mut(&mut accounts_storage.accounts, get_pool_key<T>(storage)),
      sender,
      Account<T> {
        id: object::new(ctx),
        balance: balance::zero<T>(),
        rewards_paid: 0
      }
    );
  };

  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, sender);

  let pending_rewards = 0;
  
  let account_balance_value = (balance::value(&account.balance) as u256);

  if (account_balance_value > 0) pending_rewards = (account_balance_value * pool.accrued_ipx_per_share) - account.rewards_paid;

  let token_value = coin::value(&token);

  pool.balance_value = pool.balance_value + token_value;
  balance::join(&mut account.balance, coin::into_balance(token));
  account.rewards_paid = (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share;

  event::emit(
    Stake<T> {
      pool_key: key,
      amount: token_value,
      sender,
      rewards: (pending_rewards as u64)
    }
  );

  coin::from_balance(balance::increase_supply(&mut storage.supply, (pending_rewards as u64)), ctx)
 }

 public fun unstake<T>(
  storage: &mut IPXStorage, 
  accounts_storage: &mut AccountStorage,
  coin_value: u64,
  ctx: &mut TxContext
 ): (Coin<IPX>, Coin<T>) {
  update_pool<T>(storage, ctx);
  
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  
  let account_balance_value = balance::value(&account.balance);

  assert!(account_balance_value >= coin_value, ERROR_NOT_ENOUGH_BALANCE);

  let pending_rewards = ((account_balance_value as u256) * pool.accrued_ipx_per_share) - account.rewards_paid;

  let staked_coin = coin::take(&mut account.balance, coin_value, ctx);
  pool.balance_value = pool.balance_value - coin_value;
  account.rewards_paid = (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share / scalar();

  event::emit(
    Unstake<T> {
      pool_key: key,
      amount: coin_value,
      sender: tx_context::sender(ctx),
      rewards: (pending_rewards as u64)
    }
  );

  (
    coin::from_balance(balance::increase_supply(&mut storage.supply, (pending_rewards as u64)), ctx),
    staked_coin
  )
 } 

 public fun update_all_pools(storage: &mut IPXStorage, ctx: &mut TxContext) {
  let length = table::length(&storage.pools);

  let index = 0;

  while (index < length) {
    let ipx_per_epoch = storage.ipx_per_epoch;
    let total_allocation_points = storage.total_allocation_points;

    let pool = table::borrow_mut(&mut storage.pools, index);

    update_pool_internal(pool, ipx_per_epoch, total_allocation_points, ctx);

    index = index + 1;
  }
 }  

 public fun update_pool<T>(storage: &mut IPXStorage, ctx: &mut TxContext) {
  let ipx_per_epoch = storage.ipx_per_epoch;
  let total_allocation_points = storage.total_allocation_points;

  let pool = borrow_mut_pool<T>(storage);

  update_pool_internal(pool, ipx_per_epoch, total_allocation_points, ctx);
 }

 fun update_pool_internal(
  pool: &mut Pool, 
  ipx_per_epoch: u64, 
  total_allocation_points: u64,
  ctx: &mut TxContext
  ) {
  if (pool.allocation_points == 0 || pool.balance_value == 0) return;

  let current_epoch = tx_context::epoch(ctx);

  if (current_epoch == pool.last_reward_epoch) return;

  pool.last_reward_epoch = current_epoch;

  let epochs_delta = current_epoch - pool.last_reward_epoch;

  let rewards = ((pool.allocation_points as u256) * (epochs_delta as u256) * (ipx_per_epoch as u256) / (total_allocation_points as u256));

  pool.accrued_ipx_per_share = pool.accrued_ipx_per_share + (rewards * scalar() / (pool.balance_value as u256));
 }

 fun update_ipx_pool(storage: &mut IPXStorage) {
    let total_allocation_points = storage.total_allocation_points;

    let pool = borrow_mut_pool<IPX>(storage);

    let all_other_pools_points = total_allocation_points - pool.allocation_points;

    let all_other_pools_points = all_other_pools_points / 3;

    let total_allocation_points = total_allocation_points + all_other_pools_points - pool.allocation_points;

    pool.allocation_points = all_other_pools_points;
    storage.total_allocation_points = total_allocation_points;
 } 

 fun borrow_mut_pool<T>(storage: &mut IPXStorage): &mut Pool {
  let key = get_pool_key<T>(storage);
  table::borrow_mut(&mut storage.pools, key)
 }

fun borrow_pool<T>(storage: &IPXStorage): &Pool {
  let key = get_pool_key<T>(storage);
  table::borrow(&storage.pools, key)
 }

 fun get_pool_key<T>(storage: &IPXStorage): u64 {
    table::borrow<vector<u8>, PoolKey>(&storage.pool_keys, get_coin_info<T>()).key
 }

 fun borrow_account<T>(storage: &IPXStorage, accounts_storage: &AccountStorage, sender: address): &Account<T> {
  bag::borrow(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, key: u64, sender: address): &mut Account<T> {
  bag::borrow_mut(table::borrow_mut(&mut accounts_storage.accounts, key), sender)
 }

 entry public fun update_ipx_per_epoch(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  ipx_per_epoch: u64,
  ctx: &mut TxContext
  ) {
    update_all_pools(storage, ctx);
    storage.ipx_per_epoch = ipx_per_epoch;
 }

 entry public fun add_pool<T>(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  accounts_storage: &mut AccountStorage,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  let total_allocation_points = storage.total_allocation_points;
  let start_epoch = storage.start_epoch;
  if (update) update_all_pools(storage, ctx);

  assert!(!table::contains(&storage.pool_keys, get_coin_info<T>()), ERROR_POOL_ADDED_ALREADY);

  storage.total_allocation_points = total_allocation_points + allocation_points;

  let key = table::length(&storage.pool_keys);

  assert!(!table::contains(&accounts_storage.accounts, key), ERROR_ACCOUNT_BAG_ADDED_ALREADY);

  table::add(
    &mut accounts_storage.accounts,
    key,
    bag::new(ctx)
  );

  table::add(
    &mut storage.pool_keys,
    get_coin_info<T>(),
    PoolKey {
      id: object::new(ctx),
      key
    }
  );

  let current_epoch = tx_context::epoch(ctx);

  table::add(
    &mut storage.pools,
    key,
    Pool {
      id: object::new(ctx),
      allocation_points,
      last_reward_epoch: if (current_epoch > start_epoch) { current_epoch } else { start_epoch },
      accrued_ipx_per_share: 0,
      balance_value: 0
    }
  );

  event::emit(
    AddPool<T> {
      key,
      allocation_points
    }
  );

  update_ipx_pool(storage);
 }

 entry public fun set_allocation_points<T>(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  let total_allocation_points = storage.total_allocation_points;
  if (update) update_all_pools(storage, ctx);

  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);

  if (pool.allocation_points == allocation_points) return;

  let total_allocation_points = total_allocation_points - pool.allocation_points;
  let total_allocation_points = total_allocation_points + allocation_points;

  pool.allocation_points = allocation_points;
  storage.total_allocation_points = total_allocation_points;

  event::emit(
    SetAllocationPoints<T> {
      key,
      allocation_points
    }
  );

  update_ipx_pool(storage);
 }

 entry public fun transfer_admin(
  admin: IPXAdmin,
  recipient: address
 ) {
  transfer::transfer(admin, recipient);
  event::emit(NewAdmin { admin: recipient })
 }
}
