module ipx::faucet {
   use std::ascii::String;
    use std::type_name::{get, into_string};

    use sui::bag::{Self, Bag};
    use sui::balance::{Self, Supply};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::pay;

    use ipx::coins::{Self,get_coins};
    use ipx::dex_volatile::{create_pool, Storage, VLPCoin};
    use ipx::ipx::{Self, IPXStorage, AccountStorage, IPXAdmin, IPX};
    use ipx::utils::{are_coins_sorted};


    const IPX_INITIAL_AMOUNT: u64 = 10000000000000; // 1000
    const ERROR_COIN_DOES_NOT_EXIST: u64 = 1;


    struct Faucet has key {
        id: UID,
        coins: Bag
    }

    fun init(
        ctx: &mut TxContext
    ) {
        transfer::share_object(
            Faucet {
                id: object::new(ctx),
                coins: get_coins(ctx)
            }
        )
    }

    fun mint_coins<T>(
        faucet: &mut Faucet,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let coin_name = into_string(get<T>());
        assert!(
            bag::contains_with_type<String, Supply<T>>(&faucet.coins, coin_name),
            ERROR_COIN_DOES_NOT_EXIST
        );

        let mut_supply = bag::borrow_mut<String, Supply<T>>(
            &mut faucet.coins,
            coin_name
        );

        let minted_balance = balance::increase_supply(
            mut_supply,
            amount
        );

        coin::from_balance(minted_balance, ctx)
    }

    public entry fun mint<T>(
        faucet: &mut Faucet,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        transfer::transfer(
            mint_coins<T>(faucet, amount, ctx),
            tx_context::sender(ctx)
        )
    } 

    public entry fun start_liquidity(storage: &mut Storage ,faucet: &mut Faucet, sui: Coin<SUI>, ipx: Coin<IPX>, ctx: &mut TxContext) {
      let eth = mint_coins<coins::ETH>(faucet, 50, ctx);
      let ipx_coin_value = coin::value(&ipx);

      if (ipx_coin_value > IPX_INITIAL_AMOUNT) pay::split_and_transfer(&mut ipx, ipx_coin_value - IPX_INITIAL_AMOUNT, tx_context::sender(ctx), ctx);

      if (are_coins_sorted<coins::ETH, IPX>()) {
          transfer::transfer(create_pool(storage, eth, ipx, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, ipx, eth, ctx), tx_context::sender(ctx));
      };

       let eth = mint_coins<coins::ETH>(faucet, 10, ctx);


      if (are_coins_sorted<coins::ETH, SUI>()) {
          transfer::transfer(create_pool(storage, eth, sui, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, sui, eth, ctx), tx_context::sender(ctx));
      };

    
      let eth = mint_coins<coins::ETH>(faucet, 130, ctx);
      let btc = mint_coins<coins::BTC>(faucet, 10, ctx);

      if (are_coins_sorted<coins::BTC, coins::ETH>()) {
       transfer::transfer(create_pool(storage, btc, eth, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, eth, btc, ctx), tx_context::sender(ctx));
      };

      let eth = mint_coins<coins::ETH>(faucet, 10, ctx);
      let bnb = mint_coins<coins::BNB>(faucet, 50, ctx);

      if (are_coins_sorted<coins::BNB, coins::ETH>()) {
          transfer::transfer(create_pool(storage, bnb, eth, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, eth, bnb, ctx), tx_context::sender(ctx));
      };


      let eth = mint_coins<coins::ETH>(faucet, 100, ctx);
      let usdt = mint_coins<coins::USDT>(faucet, 120000, ctx);

      if (are_coins_sorted<coins::ETH, coins::USDT>()) {
          transfer::transfer(create_pool(storage, eth, usdt, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, usdt, eth, ctx), tx_context::sender(ctx));
      };

      let eth = mint_coins<coins::ETH>(faucet, 100, ctx);
      let usdc = mint_coins<coins::USDC>(faucet, 120000, ctx);

      if (are_coins_sorted<coins::ETH, coins::USDC>()) {
          transfer::transfer(create_pool(storage, eth, usdc, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, usdc, eth, ctx), tx_context::sender(ctx));
      };

      let eth = mint_coins<coins::ETH>(faucet, 100, ctx);
      let dai = mint_coins<coins::DAI>(faucet, 120000, ctx);


      if (are_coins_sorted<coins::DAI, coins::ETH>()) {
          transfer::transfer(create_pool(storage, dai, eth, ctx), tx_context::sender(ctx));
      } else {
          transfer::transfer(create_pool(storage, eth, dai, ctx), tx_context::sender(ctx));
      };
    }

    public entry fun start_farms(
        admin_cap: &IPXAdmin,
        storage: &mut IPXStorage, 
        account_storage: &mut AccountStorage, 
        ctx: &mut TxContext
    ) {

      if (are_coins_sorted<coins::ETH, SUI>()) {
        ipx::add_pool<VLPCoin<coins::ETH, SUI>>(admin_cap, storage, account_storage, 800, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<SUI, coins::ETH>>(admin_cap, storage, account_storage, 800, false, ctx);
      };

      if (are_coins_sorted<coins::ETH, IPX>()) {
        ipx::add_pool<VLPCoin<coins::ETH, IPX>>(admin_cap, storage, account_storage, 1000, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<IPX, coins::ETH>>(admin_cap, storage, account_storage, 1000, false, ctx);
      };

      if (are_coins_sorted<coins::BTC, coins::ETH>()) {
        ipx::add_pool<VLPCoin<coins::BTC, coins::ETH>>(admin_cap, storage, account_storage, 500, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<coins::ETH, coins::BTC>>(admin_cap, storage, account_storage, 500, false, ctx);
      };

      if (are_coins_sorted<coins::BNB, coins::ETH>()) {
        ipx::add_pool<VLPCoin<coins::BNB, coins::ETH>>(admin_cap, storage, account_storage, 700, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<coins::ETH, coins::BNB>>(admin_cap, storage, account_storage, 700, false, ctx);
      };

      if (are_coins_sorted<coins::ETH, coins::USDT>()) {
        ipx::add_pool<VLPCoin<coins::ETH, coins::USDT>>(admin_cap, storage, account_storage, 600, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<coins::USDT, coins::ETH>>(admin_cap, storage, account_storage, 600, false, ctx);
      };

      if (are_coins_sorted<coins::ETH, coins::USDC>()) {
        ipx::add_pool<VLPCoin<coins::ETH, coins::USDC>>(admin_cap, storage, account_storage, 650, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<coins::USDC, coins::ETH>>(admin_cap, storage, account_storage, 650, false, ctx);
      };


      if (are_coins_sorted<coins::DAI, coins::ETH>()) {
        ipx::add_pool<VLPCoin<coins::DAI, coins::ETH>>(admin_cap, storage, account_storage, 700, false, ctx);
      } else {
        ipx::add_pool<VLPCoin<coins::ETH, coins::DAI>>(admin_cap, storage, account_storage, 700, false, ctx);
      };
    }
}
