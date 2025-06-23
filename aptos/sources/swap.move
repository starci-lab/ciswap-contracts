/// CiSwap with (X + ciX) (Y + ciY) = K
module ciswap::swap {
    use std::signer::{Self};
    use std::option::{Self};
    use std::string::{Self};
    use aptos_std::type_info::{Self};
    use aptos_std::event::{Self};

    use aptos_framework::coin::{Self};
    use aptos_framework::timestamp::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::code::{Self};

    // constants
    const ZERO_ACCOUNT: address = @zero;
    const DEFAULT_ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @ciswap;
    const DEPLOYER: address = @deployer;
    // The minimum liquidity that must be maintained in the pool
    const MINIMUM_LIQUIDITY: u128 = 1000;
    // The maximum length of the coin name
    const MAX_COIN_NAME_LENGTH: u64 = 32;

    // structs

    /// The LP Token type
    struct LPToken<phantom X, phantom Y> has key {}

    // Virtual token for the token X
    struct VirtualX<phantom X, phantom Y> has key {}

    /// The event emitted when a swap occurs
    struct AddLiquidityEvent<phantom X, phantom Y> has drop, store {
        user: address,
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
        user: address,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64
    }

    /// The event emitted when liquidity is added
    struct PairEventHolder<phantom X, phantom Y> has key {
        add_liquidity: event::EventHandle<AddLiquidityEvent<X, Y>>,
        remove_liquidity: event::EventHandle<RemoveLiquidityEvent<X, Y>>,
        swap: event::EventHandle<SwapEvent<X, Y>>
    }

    /// Stores the metadata required for the token pairs
    struct TokenPairMetadata<phantom X, phantom Y> has key {
        /// The admin of the token pair
        creator: address,
        /// fee amount , record fee amount which is not withdrawed
        fee_amount: coin::Coin<LPToken<X, Y>>,
        /// It's reserve_x * reserve_y, as of immediately after the most recent liquidity event
        k_last: u128,
        /// T0 token balance
        balance_x: coin::Coin<X>,
        /// T1 token balance
        balance_y: coin::Coin<Y>,
        /// Balance of VirtualX<X, Y>
        balance_virtual_x: coin::Coin<VirtualX<X, Y>>,
        /// Balance of VirtualX<Y, X>
        balance_virtual_y: coin::Coin<VirtualX<Y, X>>,
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
    struct TokenPairReserve<phantom X, phantom Y> has key {
        // reserve_x is the amount of T0 token in the pair
        reserve_x: u64,
        reserve_y: u64,
        // virtualization reserves
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
        // last block timestamp when the reserves were updated
        block_timestamp_last: u64
    }

    // SwapInfo is the main struct of the module, it stores the information of the swap
    struct SwapInfo has key {
        signer_cap: account::SignerCapability,
        fee_to: address,
        admin: address,
        pair_created: event::EventHandle<PairCreatedEvent>
    }
    // errors
    const ERROR_ALREADY_INITIALIZED: u64 = 0x1;
    const ERROR_NOT_ADMIN: u64 = 0x2;
    
    // events
    struct PairCreatedEvent has drop, store {
        user: address,
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
        move_to(&resource_signer, SwapInfo {
            signer_cap,
            fee_to: ZERO_ACCOUNT,
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
    public fun is_pair_created<X, Y>(): bool {
        exists<TokenPairReserve<X, Y>>(RESOURCE_ACCOUNT)
    }
    /// Create the specified coin pair
    public fun create_pair<X, Y>(
        sender: &signer,
        amount_virtual_x: u64,
        amount_virtual_y: u64
    ) acquires SwapInfo {
        assert!(!is_pair_created<X, Y>(), ERROR_ALREADY_INITIALIZED);

        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);

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
        string::append(&mut virtual_token_y_name    , name_y);
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

        move_to<TokenPairReserve<X, Y>>(
            &resource_signer,
            TokenPairReserve {
                reserve_x: 0,
                reserve_y: 0,
                reserve_virtual_x: 0,
                reserve_virtual_y: 0,
                block_timestamp_last: 0
            }
        );  

        move_to<TokenPairMetadata<X, Y>>(
            &resource_signer,
            TokenPairMetadata {
                creator: sender_addr,
                fee_amount: coin::zero<LPToken<X, Y>>(),
                k_last: 0,
                balance_x: coin::zero<X>(),
                balance_y: coin::zero<Y>(),
                balance_virtual_x,
                balance_virtual_y,
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

        move_to<PairEventHolder<X, Y>>(
            &resource_signer,
            PairEventHolder {
                add_liquidity: account::new_event_handle<AddLiquidityEvent<X, Y>>(&resource_signer),
                remove_liquidity: account::new_event_handle<RemoveLiquidityEvent<X, Y>>(&resource_signer),
                swap: account::new_event_handle<SwapEvent<X, Y>>(&resource_signer)
            }
        );

        // pair created event
        let token_x = type_info::type_name<X>();
        let token_y = type_info::type_name<Y>();

        event::emit_event<PairCreatedEvent>(
            &mut swap_info.pair_created,
            PairCreatedEvent {
                user: sender_addr,
                token_x,
                token_y,
                virtual_token_x: virtual_token_x_name,
                balance_virtual_token_x: amount_virtual_x,
                virtual_token_y: virtual_token_y_name,
                balance_virtual_token_y: amount_virtual_y
            }
        );
    }

    // Set the fee recipient address
    public entry fun set_fee_to(sender: &signer, new_fee_to: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.fee_to = new_fee_to;
    }
    
    /// The amount of balance currently in pools of the liquidity pair
    public fun token_balances<X, Y>(): (u64, u64, u64, u64) acquires TokenPairMetadata {
        let meta =
            borrow_global<TokenPairMetadata<X, Y>>(RESOURCE_ACCOUNT);
        (
            coin::value(&meta.balance_x),
            coin::value(&meta.balance_y),
            coin::value(&meta.balance_virtual_x),
            coin::value(&meta.balance_virtual_y)
        )
    }


    #[test_only]
    public fun initialize(sender: &signer) {
        init_module(sender);
    }
}