/// CiSwap with (X + ciX) (Y + ciY) = K
module ciswap::swap {
    use std::signer::{Self};
    use std::option::{Self};
    use std::string::{Self};
    use aptos_std::type_info::{Self};
    use aptos_std::event::{Self};

    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::timestamp::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::code::{Self};
    use aptos_framework::table::{Self};
    use ciswap::pool_math_utils::{Self};

    // constants
    const ZERO_ACCOUNT: address = @zero;
    const DEFAULT_ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @ciswap;
    const DEPLOYER: address = @deployer;
    // The maximum length of the coin name
    const MAX_COIN_NAME_LENGTH: u64 = 32;
    // Creation fee in apt
    const CREATION_FEE_IN_APT: u64 = 10_000_000; // 0.1 APT

    // structs

    /// The LP Token type
    struct LPToken<phantom X, phantom Y> has key {}

    // Virtual token for the token X
    struct VirtualX<phantom X, phantom Y> has key {}

    /// The event emitted when a swap occurs
    struct AddLiquidityEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address,
        pool_addr: address,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee_amount: u64
    }
    /// The event emitted when a swap occurs
    struct RemoveLiquidityEvent<phantom X, phantom Y> has drop, store {
        user: address,
        liquidity: u64,
        amount_x: u64,
        amount_y: u64,
        fee_amount: u64
    }
    /// The event emitted when a swap occurs
    struct SwapEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address,
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
        amount_out: u64,
        amount_virtual_out: u64,
        recipient_addr: address,
    }

    struct RedeemEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address,
        pool_addr: address,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
        redeemed_amount_x: u64,
        redeemed_amount_y: u64,
        recipient_addr: address
    }

    /// The event emitted when liquidity is added
    struct PairEventHolder<phantom X, phantom Y> has key {
        add_liquidity: event::EventHandle<AddLiquidityEvent<X, Y>>,
        remove_liquidity: event::EventHandle<RemoveLiquidityEvent<X, Y>>,
        swap: event::EventHandle<SwapEvent<X, Y>>,
        redeem: event::EventHandle<RedeemEvent<X, Y>>
    }

    /// Stores the metadata required for the token pairs
    struct TokenPairMetadata<phantom X, phantom Y> has key, store {
        /// The admin of the token pair
        creator: address,
        /// fee amount , record fee amount which is not withdrawed
        fee_amount: coin::Coin<LPToken<X, Y>>,
        /// It's the k_sqrt at the last mint
        k_sqrt_last: u64,
        /// T0 token balance
        balance_x: coin::Coin<X>,
        /// T1 token balance
        balance_y: coin::Coin<Y>,
        /// Balance of VirtualX<X, Y>
        balance_virtual_x: coin::Coin<VirtualX<X, Y>>,
        /// Balance of VirtualX<Y, X>
        balance_virtual_y: coin::Coin<VirtualX<Y, X>>,
        /// Balance locked liquidity, to maintain the minimum liquidity
        /// Do not count forward to fee, just a lock
        balance_locked_lp: coin::Coin<LPToken<X, Y>>,
        /// Mint capacity of LP Token
        mint_cap: coin::MintCapability<LPToken<X, Y>>,
        /// Burn capacity of LP Token
        burn_cap: coin::BurnCapability<LPToken<X, Y>>,
        /// Freeze capacity of LP Token
        freeze_cap: coin::FreezeCapability<LPToken<X, Y>>,
        /// Mint capacity of VirtualX<X, Y>
        // This is used to mint the virtual token for X
        mint_virtual_x_cap: coin::MintCapability<VirtualX<X, Y>>,
        /// Burn capacity of VirtualX<X, Y>
        burn_virtual_x_cap: coin::BurnCapability<VirtualX<X, Y>>,
        /// Freeze capacity of VirtualX<X, Y>
        freeze_virtual_x_cap: coin::FreezeCapability<VirtualX<X, Y>>,
        /// Mint capacity of VirtualX<Y, X>
        mint_virtual_y_cap: coin::MintCapability<VirtualX<Y, X>>,
        /// Burn capacity of VirtualX<Y, X>
        burn_virtual_y_cap: coin::BurnCapability<VirtualX<Y, X>>,
        /// Freeze capacity of VirtualX<Y, X>
        freeze_virtual_y_cap: coin::FreezeCapability<VirtualX<Y, X>>,
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairMetadatas<phantom X, phantom Y> has key, store {
        // The pool id is the address of the pool that were created
        metadatas: table::Table<address, TokenPairMetadata<X, Y>>,
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairReserve<phantom X, phantom Y> has key, store {
        // reserve_x is the amount of T0 token in the pair
        reserve_x: u64,
        reserve_y: u64,
        // virtualization reserves
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
        // last block timestamp when the reserves were updated
        block_timestamp_last: u64
    }

    struct TokenPairReserves<phantom X, phantom Y> has key, store {
        // The pool id is the address of the pool that were created
        reserves: table::Table<address, TokenPairReserve<X, Y>>,
    }

    // SwapInfo is the main struct of the module, it stores the information of the swap
    struct SwapInfo has key {
        signer_cap: account::SignerCapability,
        fee_to: address,
        admin: address,
        creation_fee_in_apt: u64,
        pair_created: event::EventHandle<PairCreatedEvent>
    }
    
    // errors
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_NOT_ADMIN: u64 = 2;
    const ERROR_REDEMPTION_NOT_ENOUGH: u64 = 3;
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 4;
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 5;
    const ERROR_TOKEN_NOT_SORTED: u64 = 6;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 7;
    const ERROR_INVALID_AMOUNT: u64 = 8;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 9;
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 10;
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 11;
    const ERROR_PAIR_NOT_CREATED: u64 = 12;
    const ERROR_PAIR_CREATED: u64 = 13;
    
    // events
    struct PairCreatedEvent has drop, store {
        sender_addr: address,
        pool_addr: address,
        token_x: string::String,
        token_y: string::String,
        // virtual token x
        virtual_token_x: string::String,
        balance_virtual_token_x: u64,
        // virtual token y
        virtual_token_y: string::String,
        balance_virtual_token_y: u64
    }

    // methods
    fun init_module(sender: &signer) {
        // check if the resource account already exists
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEPLOYER);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        // send the swap info to the resource account
        move_to(&resource_signer, SwapInfo {
            signer_cap,
            fee_to: ZERO_ACCOUNT,
            creation_fee_in_apt: CREATION_FEE_IN_APT,
            admin: DEFAULT_ADMIN,
            pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
        });
    }

    /// Register the LP token type in the coin module
    public fun register_lp<X, Y>(sender: &signer) {
        coin::register<LPToken<X, Y>>(sender);
    }

    /// Register the virtual token type in the coin module
    public fun register_virtual_x<X,Y>(sender: &signer) {
        coin::register<VirtualX<X,Y>>(sender);
    }

    // Check if pair is already created
    public fun is_pair_created<X, Y>(pool_addr: address): bool acquires TokenPairReserves {
        let token_pair_reserves = borrow_global<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        table::contains(&token_pair_reserves.reserves, pool_addr)
    }
    /// Create the specified coin pair
    public fun create_pair<X, Y>(
        sender: &signer,
        // pool address, will process offchain and send to the resource account
        pool_addr: address,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
    ) acquires SwapInfo, TokenPairMetadatas, TokenPairReserves {
        assert!(!is_pair_created<X, Y>(pool_addr), ERROR_ALREADY_INITIALIZED);
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);

        // transfer the creation fee in apt to the resource account
        let creation_fee = coin::withdraw<AptosCoin>(sender, swap_info.creation_fee_in_apt);
        // transfer the creation fee to the fee_to address
        coin::deposit(swap_info.fee_to, creation_fee);

        // create the LP token
        let lp_name: string::String = string::utf8(b"CiSwap-");
        let name_x = coin::symbol<X>();
        let name_y = coin::symbol<Y>();
        string::append(&mut lp_name, name_x);
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, name_y);
        string::append_utf8(&mut lp_name, b"-LP");
        if (string::length(&lp_name) > MAX_COIN_NAME_LENGTH) {
            lp_name = string::utf8(b"CiSwap LPs");
        };
        // now we init the LP token
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<LPToken<X, Y>>(
            &resource_signer,
            lp_name,
            string::utf8(b"CiSwap-LP"),
            8,
            true
        );
        // create LP CoinStore , which is needed as a lock for minimum_liquidity
        register_lp<X, Y>(&resource_signer);

        // create the virtual token
        let virtual_token_x_name: string::String = string::utf8(b"ci");
        string::append(&mut virtual_token_x_name    , name_x);
        // now we init the LP token
        let (burn_virtual_x_cap, freeze_virtual_x_cap, mint_virtual_x_cap) = coin::initialize<VirtualX<X, Y>>(
            &resource_signer,
            virtual_token_x_name,
            virtual_token_x_name,
            8,
            true
        );
        // register_virtual_T<X, Y>(&resource_signer);
        register_virtual_x<X, Y>(&resource_signer);
        // mint the virtual tokens to the resource account
        let balance_virtual_x = coin::mint<VirtualX<X, Y>>(
            amount_virtual_x,
            &mint_virtual_x_cap
        );
        let virtual_token_y_name: string::String = string::utf8(b"ci");

        string::append(&mut virtual_token_y_name, name_y);
        // now we init the LP token
        let (burn_virtual_y_cap, freeze_virtual_y_cap, mint_virtual_y_cap) = coin::initialize<VirtualX<Y, X>>(
            &resource_signer,
            virtual_token_y_name,
            virtual_token_y_name,
            8,
            true
        );
        register_virtual_x<Y, X>(&resource_signer);
        // mint the virtual tokens to the resource account
        let balance_virtual_y = coin::mint<VirtualX<Y, X>>(
            amount_virtual_y,
            &mint_virtual_y_cap
        );

        // compute the locked liquidity
        let locked_liquidity = pool_math_utils::calculate_locked_liquidity(
            amount_virtual_x,
            amount_virtual_y
        );
        // transfer the initial liquidity to the resource account
        let balance_locked_lp = coin::mint<LPToken<X, Y>>(locked_liquidity, &mint_cap);

        // check if the table containing the metadata exists
        if (!exists<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT)) {
            // create the table for the metadata
            move_to<TokenPairMetadatas<X, Y>>(
                &resource_signer,
                TokenPairMetadatas {
                    metadatas: table::new<address, TokenPairMetadata<X, Y>>()
                }
            );
        };
        // retrive the table for the metadata
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        // retrieve the last index of the table
        // move the LP token to the resource account
        table::add(
            &mut metadatas.metadatas,
            pool_addr, // the pool id is the address of the pool
            TokenPairMetadata<X, Y> {
                creator: sender_addr,
                fee_amount: coin::zero<LPToken<X, Y>>(),
                k_sqrt_last: locked_liquidity,
                balance_x: coin::zero<X>(),
                balance_y: coin::zero<Y>(),
                balance_virtual_x,
                balance_virtual_y,
                balance_locked_lp,
                mint_cap,
                burn_cap,
                freeze_cap,
                mint_virtual_x_cap,
                burn_virtual_x_cap,
                freeze_virtual_x_cap,
                mint_virtual_y_cap,
                burn_virtual_y_cap,
                freeze_virtual_y_cap
            }
        );  
        
        // check if the table containing the reserves exists
        if (!exists<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT)) {
            // create the table for the reserves
            move_to<TokenPairReserves<X, Y>>(
                &resource_signer,
                TokenPairReserves {
                    reserves: table::new<address, TokenPairReserve<X, Y>>()
                }
            );
        };

        table::add(
            &mut borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT).reserves,
            pool_addr, // the pool id is 0 for the first pool
            TokenPairReserve {
                reserve_x: 0,
                reserve_y: 0,
                reserve_virtual_x: amount_virtual_x,
                reserve_virtual_y: amount_virtual_y,
                block_timestamp_last: timestamp::now_seconds()
            }
        );

        // move the LP token to the resource account
        move_to<PairEventHolder<X, Y>>(
            &resource_signer,
            PairEventHolder {
                add_liquidity: account::new_event_handle<AddLiquidityEvent<X, Y>>(&resource_signer),
                remove_liquidity: account::new_event_handle<RemoveLiquidityEvent<X, Y>>(&resource_signer),
                swap: account::new_event_handle<SwapEvent<X, Y>>(&resource_signer),
                redeem: account::new_event_handle<RedeemEvent<X, Y>>(&resource_signer)
            }
        );

        // pair created event
        let token_x = type_info::type_name<X>();
        let token_y = type_info::type_name<Y>();

        event::emit_event<PairCreatedEvent>(
            &mut swap_info.pair_created,
            PairCreatedEvent {
                sender_addr,
                pool_addr,
                token_x,
                token_y,
                virtual_token_x: virtual_token_x_name,
                balance_virtual_token_x: amount_virtual_x,
                virtual_token_y: virtual_token_y_name,
                balance_virtual_token_y: amount_virtual_y
            }
        );
    }
    
    /// The amount of balance currently in pools of the liquidity pair
    public fun token_balances<X, Y>(pool_addr: address): (u64, u64, u64, u64) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata<X, Y>(pool_addr, metadatas);
        (
            coin::value(&metadata.balance_x),
            coin::value(&metadata.balance_y),
            coin::value(&metadata.balance_virtual_x),
            coin::value(&metadata.balance_virtual_y)
        )
    }

    // retrieve the metadata by X,Y and pool address
    public fun get_metadata<X, Y>(
        pool_addr: address, 
        metadatas: &mut TokenPairMetadatas<X, Y>
    ): &TokenPairMetadata<X, Y> {
        table::borrow(&mut metadatas.metadatas, pool_addr)  
    }

    public fun get_metadata_mut<X, Y>(
        pool_addr: address, 
        metadatas: &mut TokenPairMetadatas<X, Y>
    ): &mut TokenPairMetadata<X, Y> {
        table::borrow_mut(&mut metadatas.metadatas, pool_addr)  
    }

    // retrieve the reserve by X,Y and pool address
    public fun get_reserve<X, Y>(
        pool_addr: address,
        reserves: &mut TokenPairReserves<X, Y>
    ): &TokenPairReserve<X, Y> {
        table::borrow(&mut reserves.reserves, pool_addr)  
    }

    public fun get_reserve_mut<X, Y>(
        pool_addr: address,
        reserves: &mut TokenPairReserves<X, Y>
    ): &mut TokenPairReserve<X, Y> {
        table::borrow_mut(&mut reserves.reserves, pool_addr)  
    }

    /// Get locked liquidity in the pool
    public fun balance_locked_lp<X, Y>(pool_addr: address): u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let meta = get_metadata<X, Y>(pool_addr, metadatas);
        coin::value(&meta.balance_locked_lp)
    }

    /// Extract `amount` from this contract
    fun extract_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<X> {
        assert!(coin::value<X>(&metadata.balance_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_x, amount)
    }

    /// Extract `amount` from this contract
    fun extract_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<Y> {
        assert!(coin::value<Y>(&metadata.balance_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_y, amount)
    }

    /// Extract `amount` from this contract
    fun extract_virtual_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<X, Y>> {
        assert!(coin::value<VirtualX<X, Y>>(&metadata.balance_virtual_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_virtual_x, amount)
    }   
    /// Extract `amount` from this contract
    fun extract_virtual_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<Y, X>> {
        assert!(coin::value<VirtualX<Y, X>>(&metadata.balance_virtual_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_virtual_y, amount)
    }

    /// Redeem the token with virtual token
    public fun redeem<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
        recipient_addr: address
    ): (
        u64, 
        u64
    ) acquires TokenPairMetadatas, TokenPairReserves, PairEventHolder {
        // get the sender
        let sender_addr = signer::address_of(sender);
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        let reserve = get_reserve_mut<X, Y>(pool_addr, reserves);
        // get amount virtual x,y
        let coin_virtual_x = coin::withdraw<VirtualX<X, Y>>(sender, amount_virtual_x);
        let coin_virtual_y = coin::withdraw<VirtualX<Y, X>>(sender, amount_virtual_y);
        // get the redeemed amount
        let redeemed_amount_x = pool_math_utils::get_redeemed_amount(amount_virtual_x);
        let redeemed_amount_y = pool_math_utils::get_redeemed_amount(amount_virtual_y);
        // check if the redeemed amount is enough
        assert!(coin::value(&metadata.balance_virtual_x) >= redeemed_amount_x, ERROR_REDEMPTION_NOT_ENOUGH);
        assert!(coin::value(&metadata.balance_virtual_y) >= redeemed_amount_y, ERROR_REDEMPTION_NOT_ENOUGH);
        // burn the virtual token
        coin::burn<VirtualX<X, Y>>(coin_virtual_x, &mut metadata.burn_virtual_x_cap);
        coin::burn<VirtualX<Y, X>>(coin_virtual_y, &mut metadata.burn_virtual_y_cap);
        // mint the virtual token to the resource account to keep the liquidity
        let redeemed_x = coin::mint<VirtualX<X, Y>>(redeemed_amount_x, &mut metadata.mint_virtual_x_cap);
        let redeemed_y = coin::mint<VirtualX<Y, X>>(redeemed_amount_y, &mut metadata.mint_virtual_y_cap);
        // // get the x for y
        // depossit the redeemed amount to the metadata
        coin::merge(&mut metadata.balance_virtual_x, redeemed_x);
        coin::merge(&mut metadata.balance_virtual_y, redeemed_y);
        // depsit the tokens into recipient account
        let coin_x = extract_x<X, Y>(redeemed_amount_x, metadata);
        let coin_y = extract_y<X, Y>(redeemed_amount_y, metadata);
        coin::deposit(recipient_addr, coin_x);
        coin::deposit(recipient_addr, coin_y);
        // update the reserves
        update<X, Y>(
            reserve.reserve_x - redeemed_amount_x,
            reserve.reserve_y - redeemed_amount_y,
            reserve.reserve_virtual_x + redeemed_amount_x,
            reserve.reserve_virtual_y + redeemed_amount_y,
            reserve
        );

        // emit the redeem event
        event::emit_event<RedeemEvent<X, Y>>(
            &mut borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT).redeem,
            RedeemEvent {
                sender_addr,
                pool_addr,
                amount_virtual_x,
                amount_virtual_y,
                redeemed_amount_x,
                redeemed_amount_y,
                recipient_addr
            }
        );

        (
            redeemed_amount_x, 
            redeemed_amount_y
        )
    }

    // get the token reserves
    public fun token_reserves<X, Y>(
        pool_addr: address
    ): (
        u64, 
        u64, 
        u64,
        u64
    ) acquires TokenPairReserves {
        let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let reserve = get_reserve<X, Y>(pool_addr, reserves);
        (
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x, 
            reserve.reserve_virtual_y
        )
    }   

    fun deposit_x<X, Y>(pool_addr: address, amount: coin::Coin<X>) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr , metadatas);
        coin::merge(&mut metadata.balance_x, amount);
    }

    fun deposit_y<X, Y>(pool_addr: address, amount: coin::Coin<Y>) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        coin::merge(&mut metadata.balance_y, amount);
    }

    fun mint_lp_to<X, Y>(
        to: address,
        amount: u64,
        mint_cap: &coin::MintCapability<LPToken<X, Y>>
    ) {
        let coins = coin::mint<LPToken<X, Y>>(amount, mint_cap);
        coin::deposit(to, coins);
    }

    /// Mint LP Tokens to account
    fun mint_lp<X, Y>(amount: u64, mint_cap: &coin::MintCapability<LPToken<X, Y>>): coin::Coin<LPToken<X, Y>> {
        coin::mint<LPToken<X, Y>>(amount, mint_cap)
    }

    /// Get the total supply of LP Tokens
    public fun total_lp_supply<X, Y>(): u128 {
        option::get_with_default(
            &coin::supply<LPToken<X, Y>>(),
            0u128
        )
    }

    public fun k_sqrt<X, Y>(pool_addr: address) : u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata<X, Y>(pool_addr, metadatas);
        metadata.k_sqrt_last
    }

    public fun fee_amount<X, Y>(pool_addr: address): u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata<X, Y>(pool_addr, metadatas);
        coin::value(&metadata.fee_amount)
    }

    // mint LP tokens for the liquidity provider
    fun mint<X, Y>(pool_addr: address): (coin::Coin<LPToken<X, Y>>, u64) acquires TokenPairMetadatas, TokenPairReserves {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        let (
            balance_x, 
            balance_y, 
            balance_virtual_x,
            balance_virtual_y
        ) = (
            coin::value(&metadata.balance_x), 
            coin::value(&metadata.balance_y),
            coin::value(&metadata.balance_virtual_x),
            coin::value(&metadata.balance_virtual_y)
        );

        let reserves= borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let reserve = get_reserve_mut<X, Y>(pool_addr, reserves);
        // get the k sqrt
        let root_k_sqrt = pool_math_utils::get_k_sqrt(
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x,
            reserve.reserve_virtual_y
        );
        // get the k
        let k_sqrt = pool_math_utils::get_k_sqrt(
            balance_x, 
            balance_y, 
            balance_virtual_x,
            balance_virtual_y
        ); 
        // calculate the k difference
        // the k_diff is the difference between the current k and the k at the time of last mint
        let k_sqrt_diff = k_sqrt - root_k_sqrt; 

        // get the fee and 
        let (to_lp, fee) = pool_math_utils::get_liquidity_and_fee_amount(
            k_sqrt_diff,
        );
        // mint fee for the pool
        //let fee_amount = mint_fee<X, Y>(reserves.reserve_x, reserves.reserve_y, metadata);

        //Need to add fee amount which have not been mint.
        let lp = mint_lp<X, Y>((to_lp as u64), &metadata.mint_cap);
        let fee_coin = mint_lp<X, Y>(fee, &metadata.mint_cap);
        // merge the fee amount to the fee amount in the metadata
        coin::merge(&mut metadata.fee_amount, fee_coin);
        // update<X, Y>(balance_x, balance_y, reserves);
        metadata.k_sqrt_last = k_sqrt;
        (lp, fee)
    }

    fun add_liquidity_direct<X, Y>(
        pool_addr: address,
        x: coin::Coin<X>,
        y: coin::Coin<Y>,
    ): (
        u64, 
        u64, 
        coin::Coin<LPToken<X, Y>>, u64, 
        coin::Coin<X>, 
        coin::Coin<Y>
    ) acquires TokenPairReserves, TokenPairMetadatas {
        let amount_x = coin::value(&x);
        let amount_y = coin::value(&y);
        let (
            reserve_x, 
            reserve_y, 
            reserve_virtual_x, 
            reserve_virtual_y
        ) = token_reserves<X, Y>(pool_addr);
        let (a_x, a_y) = {
            let amount_y_optimal = pool_math_utils::quote(
                amount_x, 
                reserve_x, 
                reserve_y, 
                reserve_virtual_x,
                reserve_virtual_y
                );
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal = pool_math_utils::quote(
                    amount_y, 
                    reserve_y,
                    reserve_x,
                    reserve_virtual_y,
                    reserve_virtual_x
                );
                assert!(amount_x_optimal <= amount_x, ERROR_INVALID_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        assert!(a_x <= amount_x, ERROR_INSUFFICIENT_AMOUNT);
        assert!(a_y <= amount_y, ERROR_INSUFFICIENT_AMOUNT);

        let left_x = coin::extract(&mut x, amount_x - a_x);
        let left_y = coin::extract(&mut y, amount_y - a_y);
        deposit_x<X, Y>(pool_addr, x);
        deposit_y<X, Y>(pool_addr, y);
        let (lp, fee_amount) = mint<X, Y>(pool_addr);
        (a_x, a_y, lp, fee_amount, left_x, left_y)
    }

    public fun check_or_register_coin_store<X>(sender: &signer) {
        if (!coin::is_account_registered<X>(signer::address_of(sender))) {
            coin::register<X>(sender);
        };
    }

    public fun add_liquidity<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64, u64) acquires TokenPairReserves, TokenPairMetadatas, PairEventHolder {
        let (a_x, a_y, coin_lp, fee_amount, coin_left_x, coin_left_y) = add_liquidity_direct(
            pool_addr, 
            coin::withdraw<X>(sender, amount_x), 
            coin::withdraw<Y>(sender, amount_y)
        );
        let sender_addr = signer::address_of(sender);
        let lp_amount = coin::value(&coin_lp);
        assert!(lp_amount > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        check_or_register_coin_store<LPToken<X, Y>>(sender);
        coin::deposit(sender_addr, coin_lp);
        coin::deposit(sender_addr, coin_left_x);
        coin::deposit(sender_addr, coin_left_y);

        let pair_event_holder = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
        event::emit_event<AddLiquidityEvent<X, Y>>(
            &mut pair_event_holder.add_liquidity,
            AddLiquidityEvent<X, Y> {
                sender_addr,
                pool_addr,
                amount_x: a_x,
                amount_y: a_y,
                liquidity: lp_amount,
                fee_amount: (fee_amount as u64),
            }
        );
        (a_x, a_y, lp_amount)
    }

    public entry fun set_fee_to(sender: &signer, new_fee_to: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.fee_to = new_fee_to;
    }

    public entry fun set_admin(sender: &signer, new_admin: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.admin = new_admin;
    }

    public entry fun upgrade_swap(
        sender: &signer, 
        metadata_serialized: vector<u8>, 
        code: vector<vector<u8>>
    ) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);
        code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    fun update<X, Y>(
        balance_x: u64, 
        balance_y: u64, 
        balance_virtual_x: u64, 
        balance_virtual_y: u64,
        reserve: &mut TokenPairReserve<X, Y>
    ) {
        let block_timestamp = timestamp::now_seconds();
        reserve.reserve_x = balance_x;
        reserve.reserve_y = balance_y;
        reserve.reserve_virtual_x = balance_virtual_x;
        reserve.reserve_virtual_y = balance_virtual_y;
        reserve.block_timestamp_last = block_timestamp;
    }

    /// in ciswap, we use amount_x_in and amount_y_in to calculate the output amount
    /// because the output depends on the token that the
    public fun swap<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
        recipient_addr: address,
        limit_amount_calculated: u64
    ): (
        u64, u64
    ) acquires PairEventHolder, TokenPairMetadatas, TokenPairReserves {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let reserve =  get_reserve_mut<X, Y>(pool_addr, reserves);
        // no need to check amount out
        //assert!(amount_x_out < reserves.reserve_x && amount_y_out < reserves.reserve_y, ERROR_INSUFFICIENT_LIQUIDITY);
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        // quoute the amount out
        let (
            amount_out, 
            amount_virtual_out
        ) = pool_math_utils::get_tokens_amount_out(
            amount_in, 
            x_for_y, 
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x, 
            reserve.reserve_virtual_y
        );

        // get the actual reserves
        let (actual_x, actual_y) = pool_math_utils::get_actual_x_y(
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x, 
            reserve.reserve_virtual_y
        );
        // check if the amount out is less than the actual reserves
        if (x_for_y) {
            let coin = coin::withdraw<X>(sender, amount_in);
            // deposit the token x to the pool
            coin::merge(&mut metadata.balance_x, coin);
            // if x_for_y, then reserve_x is the T0 token
            assert!(amount_out <= actual_y, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            // define the coins to be returned
            let coins_y_out = coin::zero<Y>();
            let virtual_coins_y_out = coin::zero<VirtualX<Y, X>>();
            // do transfer the token x to the sender
            coin::merge(
                &mut coins_y_out, 
                extract_y(
                    amount_out, 
                    metadata
                )
            );
            // do transfer the virtual token x to the sender
            coin::merge(
                &mut virtual_coins_y_out, 
                extract_virtual_y(
                    amount_virtual_out, 
                    metadata
                )
            );
            // slippage protection
            assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            // update reserves
            reserve.reserve_y -= amount_out;
            reserve.reserve_virtual_y -= amount_virtual_out;
            reserve.reserve_x += amount_in;

            // deposit the token y to the recipient addr
            coin::deposit(recipient_addr, coins_y_out);
            coin::deposit(recipient_addr, virtual_coins_y_out);
        } else {
            let coin = coin::withdraw<Y>(sender, amount_in);
            // deposit the token x to the pool
            coin::merge(&mut metadata.balance_y, coin);
            // if x_for_y, then reserve_x is the T0 token
            assert!(amount_out <= actual_x, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            // do transfer the token x to the sender
            let coins_x_out = coin::zero<X>();
            let virtual_coins_x_out = coin::zero<VirtualX<X, Y>>();

            // do transfer the token x to the sender
            coin::merge(
                &mut coins_x_out, 
                extract_x(
                    amount_out, 
                    metadata
                )
            );
            // slippage protection
            assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            // do transfer the virtual token x to the sender
            coin::merge(
                &mut virtual_coins_x_out, 
                extract_virtual_x(
                    amount_virtual_out, 
                    metadata
                )
            );
            // update reserves
            reserve.reserve_x -= amount_out;
            reserve.reserve_virtual_x -= amount_virtual_out;
            reserve.reserve_y += amount_in;

            // deposit the token y to the recipient
            coin::deposit(recipient_addr, coins_x_out);
            coin::deposit(recipient_addr, virtual_coins_x_out);
        };

        // emit the swap event
        emit_swap_event<X, Y>(
            signer::address_of(sender),
            pool_addr,
            amount_in,
            x_for_y,
            amount_out,
            amount_virtual_out,
            recipient_addr
        );
        // return the amount out and the virtual amount out
        (amount_out, amount_virtual_out)
    }

    public fun emit_swap_event<X, Y>(
        sender_addr: address,
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
        amount_out: u64,
        amount_virtual_out: u64,
        recipient_addr: address
    ) acquires PairEventHolder {
        let pair_event_holder = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
        event::emit_event<SwapEvent<X, Y>>(
            &mut pair_event_holder.swap,
            SwapEvent<X, Y> {
                sender_addr,
                pool_addr,
                amount_in,
                x_for_y,
                amount_out,
                amount_virtual_out,
                recipient_addr
            }
        );
    }

    public fun get_amount_out<X, Y>(
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool
    ): (u64, u64) acquires TokenPairReserves {
        let (
            reserve_x, 
            reserve_y, 
            reserve_virtual_x, 
            reserve_virtual_y
        ) = token_reserves<X, Y>(pool_addr);
        pool_math_utils::get_tokens_amount_out(
            amount_in, 
            x_for_y, 
            reserve_x, 
            reserve_y, 
            reserve_virtual_x, 
            reserve_virtual_y
        )
    }

    public fun get_amount_in<X, Y>(
        pool_addr: address,
        amount_out: u64,
        x_for_y: bool
    ): ( u64 ) acquires TokenPairReserves {
        let (
            reserve_x, 
            reserve_y, 
            reserve_virtual_x, 
            reserve_virtual_y
        ) = token_reserves<X, Y>(pool_addr);
        pool_math_utils::get_amount_in(
            amount_out,
            x_for_y,
            reserve_x,
            reserve_y,
            reserve_virtual_x,
            reserve_virtual_y,
        )
    }

    public fun is_pair_created_internal<X, Y>(pool_addr: address) acquires TokenPairReserves {
        assert!(
            is_pair_created<X, Y>(pool_addr) || is_pair_created<Y, X>(pool_addr), 
            ERROR_PAIR_NOT_CREATED
        );
    }

    public fun is_pair_not_create_internal<X, Y>(pool_addr: address) acquires TokenPairReserves {
        assert!(
            !is_pair_created<X, Y>(pool_addr) && !is_pair_created<Y, X>(pool_addr), 
            ERROR_PAIR_CREATED
        );
    }

    #[test_only]
    public fun initialize(sender: &signer) {
        init_module(sender);
    }
}