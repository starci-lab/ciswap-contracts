/// CiSwap with (X + ciX) (Y + ciY) = K
module ciswap::swap {
    // Importing necessary modules from the standard library, Aptos framework, and local modules
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

    // ------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------
    // Addresses and configuration constants for the module
    const ZERO_ACCOUNT: address = @zero; // Placeholder zero address
    const DEFAULT_ADMIN: address = @default_admin; // Default admin address
    const DEFAULT_FEE_TO: address = @fee_to; // Default fee recipient address
    const RESOURCE_ACCOUNT: address = @ciswap; // Resource account for the module
    const DEPLOYER: address = @deployer; // Deployer address
    const MAX_COIN_NAME_LENGTH: u64 = 32; // The maximum length of the coin name
    const CREATION_FEE_IN_APT: u64 = 10_000_000; // 0.1 APT, fee for creating a new pair

    // ------------------------------------------------------------------------
    // Structs
    // ------------------------------------------------------------------------

    /// The LP Token type, representing liquidity provider tokens for a pair.
    ///
    /// # Type Parameters
    /// - `X`: The first token type in the pair (phantom, not stored directly)
    /// - `Y`: The second token type in the pair (phantom, not stored directly)
    struct LPToken<phantom X, phantom Y> has key {}

    /// Virtual token for the token X in a pair (used for virtual liquidity).
    ///
    /// # Type Parameters
    /// - `X`: The token this virtual token represents (phantom)
    /// - `Y`: The other token in the pair (phantom)
    struct VirtualX<phantom X, phantom Y> has key {}

    /// The event emitted when liquidity is added to a pool.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the liquidity provider
    /// - `pool_addr`: Address of the pool
    /// - `amount_x`: Amount of token X added
    /// - `amount_y`: Amount of token Y added
    /// - `liquidity`: Amount of LP tokens minted
    /// - `fee_amount`: Fee amount collected
    struct AddLiquidityEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address, // Address of the liquidity provider
        pool_addr: address,   // Address of the pool
        amount_x: u64,        // Amount of token X added
        amount_y: u64,        // Amount of token Y added
        liquidity: u64,       // Amount of LP tokens minted
        fee_amount: u64       // Fee amount collected
    }
    /// The event emitted when liquidity is removed from a pool.
    ///
    /// # Fields
    /// - `user`: Address of the user removing liquidity
    /// - `liquidity`: Amount of LP tokens burned
    /// - `amount_x`: Amount of token X withdrawn
    /// - `amount_y`: Amount of token Y withdrawn
    /// - `fee_amount`: Fee amount collected
    struct RemoveLiquidityEvent<phantom X, phantom Y> has drop, store {
        user: address,        // Address of the user removing liquidity
        liquidity: u64,       // Amount of LP tokens burned
        amount_x: u64,        // Amount of token X withdrawn
        amount_y: u64,        // Amount of token Y withdrawn
        fee_amount: u64       // Fee amount collected
    }
    /// The event emitted when a swap occurs.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the swap initiator
    /// - `pool_addr`: Address of the pool
    /// - `amount_in`: Amount of input token
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `amount_out`: Amount of output token
    /// - `amount_virtual_out`: Amount of virtual output token
    /// - `recipient_addr`: Address receiving the output
    struct SwapEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address,     // Address of the swap initiator
        pool_addr: address,       // Address of the pool
        amount_in: u64,           // Amount of input token
        x_for_y: bool,            // Direction of swap (true if X for Y)
        amount_out: u64,          // Amount of output token
        amount_virtual_out: u64,  // Amount of virtual output token
        recipient_addr: address,  // Address receiving the output
    }

    /// The event emitted when virtual tokens are redeemed for real tokens.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the redeemer
    /// - `pool_addr`: Address of the pool
    /// - `amount_virtual_x`: Amount of virtual X redeemed
    /// - `amount_virtual_y`: Amount of virtual Y redeemed
    /// - `redeemed_amount_x`: Amount of real X received
    /// - `redeemed_amount_y`: Amount of real Y received
    /// - `recipient_addr`: Address receiving the real tokens
    struct RedeemEvent<phantom X, phantom Y> has drop, store {
        sender_addr: address,         // Address of the redeemer
        pool_addr: address,           // Address of the pool
        amount_virtual_x: u64,        // Amount of virtual X redeemed
        amount_virtual_y: u64,        // Amount of virtual Y redeemed
        redeemed_amount_x: u64,       // Amount of real X received
        redeemed_amount_y: u64,       // Amount of real Y received
        recipient_addr: address       // Address receiving the real tokens
    }

    /// Holds all event handles for a pair (add/remove liquidity, swap, redeem).
    ///
    /// # Fields
    /// - `add_liquidity`: Event handle for AddLiquidityEvent
    /// - `remove_liquidity`: Event handle for RemoveLiquidityEvent
    /// - `swap`: Event handle for SwapEvent
    /// - `redeem`: Event handle for RedeemEvent
    struct PairEventHolder<phantom X, phantom Y> has key {
        add_liquidity: event::EventHandle<AddLiquidityEvent<X, Y>>,
        remove_liquidity: event::EventHandle<RemoveLiquidityEvent<X, Y>>,
        swap: event::EventHandle<SwapEvent<X, Y>>,
        redeem: event::EventHandle<RedeemEvent<X, Y>>
    }

    /// Stores metadata for a token pair, including balances and capabilities.
    ///
    /// # Fields
    /// - `creator`: Creator/admin of the pair
    /// - `fee_amount`: Accumulated fees in LP tokens
    /// - `k_sqrt_last`: Last recorded sqrt(K) for fee calculation
    /// - `balance_x`: Pool balance of token X
    /// - `balance_y`: Pool balance of token Y
    /// - `balance_virtual_x`: Virtual X balance
    /// - `balance_virtual_y`: Virtual Y balance
    /// - `balance_locked_lp`: Locked LP tokens (minimum liquidity)
    /// - `mint_cap`, `burn_cap`, `freeze_cap`: Capabilities for LP tokens
    /// - `mint_virtual_x_cap`, `burn_virtual_x_cap`, `freeze_virtual_x_cap`: Capabilities for virtual X
    /// - `mint_virtual_y_cap`, `burn_virtual_y_cap`, `freeze_virtual_y_cap`: Capabilities for virtual Y
    struct TokenPairMetadata<phantom X, phantom Y> has key, store {
        creator: address, // Address of the user who created the pair (admin for this pair)
        fee_amount: coin::Coin<LPToken<X, Y>>, // Accumulated fees in LP tokens (not yet withdrawn)
        k_sqrt_last: u64, // Last recorded sqrt(K) for fee calculation (used for fee distribution)
        balance_x: coin::Coin<X>, // Pool's current balance of token X
        balance_y: coin::Coin<Y>, // Pool's current balance of token Y
        balance_virtual_x: coin::Coin<VirtualX<X, Y>>, // Pool's current balance of virtual X
        balance_virtual_y: coin::Coin<VirtualX<Y, X>>, // Pool's current balance of virtual Y
        balance_locked_lp: coin::Coin<LPToken<X, Y>>, // Minimum liquidity locked in the pool (cannot be withdrawn)
        mint_cap: coin::MintCapability<LPToken<X, Y>>, // Capability to mint LP tokens
        burn_cap: coin::BurnCapability<LPToken<X, Y>>, // Capability to burn LP tokens
        freeze_cap: coin::FreezeCapability<LPToken<X, Y>>, // Capability to freeze LP tokens
        mint_virtual_x_cap: coin::MintCapability<VirtualX<X, Y>>, // Capability to mint virtual X
        burn_virtual_x_cap: coin::BurnCapability<VirtualX<X, Y>>, // Capability to burn virtual X
        freeze_virtual_x_cap: coin::FreezeCapability<VirtualX<X, Y>>, // Capability to freeze virtual X
        mint_virtual_y_cap: coin::MintCapability<VirtualX<Y, X>>, // Capability to mint virtual Y
        burn_virtual_y_cap: coin::BurnCapability<VirtualX<Y, X>>, // Capability to burn virtual Y
        freeze_virtual_y_cap: coin::FreezeCapability<VirtualX<Y, X>>, // Capability to freeze virtual Y
    }

    /// Table of all TokenPairMetadata for a given pair type.
    ///
    /// # Fields
    /// - `metadatas`: Table mapping pool address to TokenPairMetadata
    struct TokenPairMetadatas<phantom X, phantom Y> has key, store {
        metadatas: table::Table<address, TokenPairMetadata<X, Y>>, // Mapping pool address to metadata
    }

    /// Reserve information for a token pair (real and virtual reserves).
    ///
    /// # Fields
    /// - `reserve_x`: Real reserve of token X
    /// - `reserve_y`: Real reserve of token Y
    /// - `reserve_virtual_x`: Virtual reserve of X
    /// - `reserve_virtual_y`: Virtual reserve of Y
    /// - `block_timestamp_last`: Last update timestamp
    struct TokenPairReserve<phantom X, phantom Y> has key, store {
        reserve_x: u64, // Real reserve of token X
        reserve_y: u64, // Real reserve of token Y
        reserve_virtual_x: u64, // Virtual reserve of X
        reserve_virtual_y: u64, // Virtual reserve of Y
        block_timestamp_last: u64 // Last update timestamp (seconds)
    }

    /// Table of all TokenPairReserve for a given pair type.
    ///
    /// # Fields
    /// - `reserves`: Table mapping pool address to TokenPairReserve
    struct TokenPairReserves<phantom X, phantom Y> has key, store {
        reserves: table::Table<address, TokenPairReserve<X, Y>>, // Mapping pool address to reserves
    }

    /// Main module resource, stores admin, fee info, and event handle for pair creation.
    ///
    /// # Fields
    /// - `signer_cap`: Capability to sign as resource account
    /// - `fee_to`: Address to receive protocol fees
    /// - `fee_amount_apt`: Accumulated fees in APT
    /// - `admin`: Admin address
    /// - `creation_fee_in_apt`: Fee for creating a new pair
    /// - `pair_created`: Event handle for pair creation
    struct SwapInfo has key {
        signer_cap: account::SignerCapability, // Capability to sign as resource account
        fee_to: address, // Address to receive protocol fees
        fee_amount_apt: coin::Coin<AptosCoin>, // Accumulated fees in APT
        admin: address, // Admin address
        creation_fee_in_apt: u64, // Fee for creating a new pair
        pair_created: event::EventHandle<PairCreatedEvent> // Event handle for pair creation
    }

    // ------------------------------------------------------------------------
    // Error Codes
    // ------------------------------------------------------------------------
    // Error codes for various failure conditions
    const ERROR_ALREADY_INITIALIZED: u64 = 1; // Pair already initialized
    const ERROR_NOT_ADMIN: u64 = 2; // Not admin
    const ERROR_REDEMPTION_NOT_ENOUGH: u64 = 3; // Not enough tokens to redeem
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 4; // Token A balance not zero
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 5; // Token B balance not zero
    const ERROR_TOKEN_NOT_SORTED: u64 = 6; // Token types not sorted
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 7; // Insufficient amount
    const ERROR_INVALID_AMOUNT: u64 = 8; // Invalid amount
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 9; // Insufficient liquidity
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 10; // Insufficient input amount
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 11; // Insufficient output amount
    const ERROR_PAIR_NOT_CREATED: u64 = 12; // Pair not created
    const ERROR_PAIR_CREATED: u64 = 13; // Pair already created

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    /// Event emitted when a new pair is created.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the creator
    /// - `pool_addr`: Address of the new pool
    /// - `token_x`: Name of token X
    /// - `token_y`: Name of token Y
    /// - `virtual_token_x`: Name of virtual token X
    /// - `balance_virtual_token_x`: Initial virtual X balance
    /// - `virtual_token_y`: Name of virtual token Y
    /// - `balance_virtual_token_y`: Initial virtual Y balance
    struct PairCreatedEvent has drop, store {
        sender_addr: address, // Address of the creator
        pool_addr: address,   // Address of the new pool
        token_x: string::String, // Name of token X
        token_y: string::String, // Name of token Y
        virtual_token_x: string::String, // Name of virtual token X
        balance_virtual_token_x: u64,    // Initial virtual X balance
        virtual_token_y: string::String, // Name of virtual token Y
        balance_virtual_token_y: u64     // Initial virtual Y balance
    }

    // ------------------------------------------------------------------------
    // Core Methods
    // ------------------------------------------------------------------------

    /// Initializes the module by creating the SwapInfo resource in the resource account.
    ///
    /// # Arguments
    /// - `sender`: The deployer signer
    ///
    /// # Effects
    /// - Creates the SwapInfo resource in the resource account
    /// - Sets up admin, fee recipient, and event handle
    fun init_module(sender: &signer) {
        // Retrieve the resource account capability for the deployer
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEPLOYER);
        // Create a signer for the resource account
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        // Store SwapInfo in the resource account
        move_to(&resource_signer, SwapInfo {
            signer_cap,
            fee_to: DEFAULT_FEE_TO,
            fee_amount_apt: coin::zero<AptosCoin>(),
            creation_fee_in_apt: CREATION_FEE_IN_APT,
            admin: DEFAULT_ADMIN,
            pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
        });
    }

    /// Registers the LP token type for a pair in the coin module.
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Token types for the LP token
    /// # Arguments
    /// - `sender`: The signer to register the coin store
    public fun register_lp<X, Y>(sender: &signer) {
        coin::register<LPToken<X, Y>>(sender);
    }

    /// Registers the virtual token type for a pair in the coin module.
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Token types for the virtual token
    /// # Arguments
    /// - `sender`: The signer to register the coin store
    public fun register_virtual_x<X,Y>(sender: &signer) {
        coin::register<VirtualX<X,Y>>(sender);
    }

    /// Checks if a pair is already created for the given pool address.
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Token types for the pair
    /// # Arguments
    /// - `pool_addr`: Address of the pool
    /// # Returns
    /// - `bool`: True if the pair exists, false otherwise
    public fun is_pair_created<X, Y>(pool_addr: address): bool acquires TokenPairReserves {
        // If the reserves table does not exist, the pair is not created
        if (!exists<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT)) {
            return false;
        };
        // Check if the reserves table contains the pool address
        let token_pair_reserves = borrow_global<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        table::contains(&token_pair_reserves.reserves, pool_addr)
    }

    /// Creates a new token pair pool with specified virtual balances.
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Token types for the pair
    /// # Arguments
    /// - `sender`: The signer creating the pair
    /// - `pool_addr`: Pool address (provided off-chain)
    /// - `amount_virtual_x`: Initial virtual X liquidity
    /// - `amount_virtual_y`: Initial virtual Y liquidity
    ///
    /// # Effects
    /// - Checks that the pair is not already created
    /// - Transfers creation fee
    /// - Initializes LP and virtual tokens
    /// - Stores metadata and reserves
    /// - Emits PairCreatedEvent
    public fun create_pair<X, Y>(
        sender: &signer,
        pool_addr: address, // Pool address, provided off-chain
        amount_virtual_x: u64, // Initial virtual X liquidity
        amount_virtual_y: u64  // Initial virtual Y liquidity
    ) acquires SwapInfo, TokenPairMetadatas, TokenPairReserves {
        // --------------------------------------------------------------------
        // 1. Check that the pair is not already initialized
        assert!(!is_pair_created<X, Y>(pool_addr), ERROR_ALREADY_INITIALIZED);
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);

        // --------------------------------------------------------------------
        // 2. Transfer the creation fee in APT to the resource account
        let creation_fee = coin::withdraw<AptosCoin>(sender, swap_info.creation_fee_in_apt);
        coin::merge(&mut swap_info.fee_amount_apt, creation_fee);

        // --------------------------------------------------------------------
        // 3. Create the LP token for this pair
        // Compose LP token name: "CiSwap-<X>-<Y>-LP"
        let lp_name: string::String = string::utf8(b"CiSwap-");
        let name_x = coin::symbol<X>();
        let name_y = coin::symbol<Y>();
        string::append(&mut lp_name, name_x);
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, name_y);
        string::append_utf8(&mut lp_name, b"-LP");
        // If name is too long, use a generic name
        if (string::length(&lp_name) > MAX_COIN_NAME_LENGTH) {
            lp_name = string::utf8(b"CiSwap LPs");
        };
        // Initialize the LP token and get capabilities
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<LPToken<X, Y>>(
            &resource_signer,
            lp_name,
            string::utf8(b"CiSwap-LP"),
            8,
            true
        );
        // Register LP CoinStore for minimum liquidity lock
        register_lp<X, Y>(&resource_signer);

        // --------------------------------------------------------------------
        // 4. Create and register the virtual token X
        let virtual_token_x_name: string::String = string::utf8(b"ci");
        string::append(&mut virtual_token_x_name    , name_x);
        let (burn_virtual_x_cap, freeze_virtual_x_cap, mint_virtual_x_cap) = coin::initialize<VirtualX<X, Y>>(
            &resource_signer,
            virtual_token_x_name,
            virtual_token_x_name,
            8,
            true
        );
        register_virtual_x<X, Y>(&resource_signer);
        // Mint the initial virtual X tokens to the resource account
        let balance_virtual_x = coin::mint<VirtualX<X, Y>>(
            amount_virtual_x,
            &mint_virtual_x_cap
        );
        // 5. Create and register the virtual token Y
        let virtual_token_y_name: string::String = string::utf8(b"ci");
        string::append(&mut virtual_token_y_name, name_y);
        let (burn_virtual_y_cap, freeze_virtual_y_cap, mint_virtual_y_cap) = coin::initialize<VirtualX<Y, X>>(
            &resource_signer,
            virtual_token_y_name,
            virtual_token_y_name,
            8,
            true
        );
        register_virtual_x<Y, X>(&resource_signer);
        // Mint the initial virtual Y tokens to the resource account
        let balance_virtual_y = coin::mint<VirtualX<Y, X>>(
            amount_virtual_y,
            &mint_virtual_y_cap
        );

        // --------------------------------------------------------------------
        // 6. Compute the minimum locked liquidity for the pool
        let locked_liquidity = pool_math_utils::calculate_locked_liquidity(
            amount_virtual_x,
            amount_virtual_y
        );
        // Mint the locked LP tokens to the resource account
        let balance_locked_lp = coin::mint<LPToken<X, Y>>(locked_liquidity, &mint_cap);

        // --------------------------------------------------------------------
        // 7. Create the metadata table if it doesn't exist
        if (!exists<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT)) {
            move_to<TokenPairMetadatas<X, Y>>(
                &resource_signer,
                TokenPairMetadatas {
                    metadatas: table::new<address, TokenPairMetadata<X, Y>>()
                }
            );
        };
        // Add the new pair's metadata to the table
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        table::add(
            &mut metadatas.metadatas,
            pool_addr, // Pool id is the address of the pool
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
        
        // --------------------------------------------------------------------
        // 8. Create the reserves table if it doesn't exist
        if (!exists<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT)) {
            move_to<TokenPairReserves<X, Y>>(
                &resource_signer,
                TokenPairReserves {
                    reserves: table::new<address, TokenPairReserve<X, Y>>()
                }
            );
        };

        // Add the new pair's reserves to the table
        let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let block_timestamp_last = timestamp::now_seconds();
        table::add(
            &mut reserves.reserves,
            pool_addr, // Pool id is the address of the pool
            TokenPairReserve {
                reserve_x: 0,
                reserve_y: 0,
                reserve_virtual_x: amount_virtual_x,
                reserve_virtual_y: amount_virtual_y,
                block_timestamp_last
            }
        );

        // --------------------------------------------------------------------
        // 9. Create and store the event holder for this pair
        move_to<PairEventHolder<X, Y>>(
            &resource_signer,
            PairEventHolder {
                add_liquidity: account::new_event_handle<AddLiquidityEvent<X, Y>>(&resource_signer),
                remove_liquidity: account::new_event_handle<RemoveLiquidityEvent<X, Y>>(&resource_signer),
                swap: account::new_event_handle<SwapEvent<X, Y>>(&resource_signer),
                redeem: account::new_event_handle<RedeemEvent<X, Y>>(&resource_signer)
            }
        );

        // --------------------------------------------------------------------
        // 10. Emit the pair created event
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

    /// Returns the current balances of X, Y, virtual X, and virtual Y in the pool
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
    /// Returns a reference to the metadata for a given pool address
    public fun get_metadata<X, Y>(
        pool_addr: address, 
        metadatas: &mut TokenPairMetadatas<X, Y>
    ): &TokenPairMetadata<X, Y> {
        table::borrow(&mut metadatas.metadatas, pool_addr)  
    }

    /// Returns a mutable reference to the metadata for a given pool address
    public fun get_metadata_mut<X, Y>(
        pool_addr: address, 
        metadatas: &mut TokenPairMetadatas<X, Y>
    ): &mut TokenPairMetadata<X, Y> {
        table::borrow_mut(&mut metadatas.metadatas, pool_addr)  
    }

    // retrieve the reserve by X,Y and pool address
    /// Returns a reference to the reserves for a given pool address
    public fun get_reserve<X, Y>(
        pool_addr: address,
        reserves: &mut TokenPairReserves<X, Y>
    ): &TokenPairReserve<X, Y> {
        table::borrow(&mut reserves.reserves, pool_addr)  
    }

    /// Returns a mutable reference to the reserves for a given pool address
    public fun get_reserve_mut<X, Y>(
        pool_addr: address,
        reserves: &mut TokenPairReserves<X, Y>
    ): &mut TokenPairReserve<X, Y> {
        table::borrow_mut(&mut reserves.reserves, pool_addr)  
    }

    /// Returns the amount of locked LP tokens in the pool
    public fun balance_locked_lp<X, Y>(pool_addr: address): u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let meta = get_metadata<X, Y>(pool_addr, metadatas);
        coin::value(&meta.balance_locked_lp)
    }

    /// Extracts a specified amount of X from the pool's balance (internal use)
    fun extract_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<X> {
        assert!(coin::value<X>(&metadata.balance_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_x, amount)
    }

    /// Extracts a specified amount of Y from the pool's balance (internal use)
    fun extract_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<Y> {
        assert!(coin::value<Y>(&metadata.balance_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_y, amount)
    }

    /// Extracts a specified amount of virtual X from the pool's balance (internal use)
    fun extract_virtual_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<X, Y>> {
        assert!(coin::value<VirtualX<X, Y>>(&metadata.balance_virtual_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_virtual_x, amount)
    }   
    /// Extracts a specified amount of virtual Y from the pool's balance (internal use)
    fun extract_virtual_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<Y, X>> {
        assert!(coin::value<VirtualX<Y, X>>(&metadata.balance_virtual_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut metadata.balance_virtual_y, amount)
    }

    /// Redeems virtual tokens for real tokens, transferring them to the recipient
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
        // Get references to metadata and reserves
        let sender_addr = signer::address_of(sender);
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        let reserve = get_reserve_mut<X, Y>(pool_addr, reserves);
        // Withdraw virtual tokens from sender
        let coin_virtual_x = coin::withdraw<VirtualX<X, Y>>(sender, amount_virtual_x);
        let coin_virtual_y = coin::withdraw<VirtualX<Y, X>>(sender, amount_virtual_y);
        // Calculate the real tokens to be redeemed
        let redeemed_amount_x = pool_math_utils::get_redeemed_amount(amount_virtual_x);
        let redeemed_amount_y = pool_math_utils::get_redeemed_amount(amount_virtual_y);
        // Ensure the pool has enough real tokens to redeem
        assert!(coin::value(&metadata.balance_virtual_x) >= redeemed_amount_x, ERROR_REDEMPTION_NOT_ENOUGH);
        assert!(coin::value(&metadata.balance_virtual_y) >= redeemed_amount_y, ERROR_REDEMPTION_NOT_ENOUGH);
        // Burn the virtual tokens
        coin::burn<VirtualX<X, Y>>(coin_virtual_x, &mut metadata.burn_virtual_x_cap);
        coin::burn<VirtualX<Y, X>>(coin_virtual_y, &mut metadata.burn_virtual_y_cap);
        // Mint new virtual tokens to the pool to maintain liquidity
        let redeemed_x = coin::mint<VirtualX<X, Y>>(redeemed_amount_x, &mut metadata.mint_virtual_x_cap);
        let redeemed_y = coin::mint<VirtualX<Y, X>>(redeemed_amount_y, &mut metadata.mint_virtual_y_cap);
        // Add the new virtual tokens to the pool's balance
        coin::merge(&mut metadata.balance_virtual_x, redeemed_x);
        coin::merge(&mut metadata.balance_virtual_y, redeemed_y);
        // Extract real tokens from the pool and deposit to recipient
        let coin_x = extract_x<X, Y>(redeemed_amount_x, metadata);
        let coin_y = extract_y<X, Y>(redeemed_amount_y, metadata);
        coin::deposit(recipient_addr, coin_x);
        coin::deposit(recipient_addr, coin_y);
        // Update the reserves to reflect the redemption
        update<X, Y>(
            reserve.reserve_x - redeemed_amount_x,
            reserve.reserve_y - redeemed_amount_y,
            reserve.reserve_virtual_x + redeemed_amount_x,
            reserve.reserve_virtual_y + redeemed_amount_y,
            reserve
        );

        // Emit the redeem event
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

    /// Returns the current reserves (real and virtual) for a pool
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

    /// Deposits X into the pool's balance (internal use)
    fun deposit_x<X, Y>(pool_addr: address, amount: coin::Coin<X>) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr , metadatas);
        coin::merge(&mut metadata.balance_x, amount);
    }

    /// Deposits Y into the pool's balance (internal use)
    fun deposit_y<X, Y>(pool_addr: address, amount: coin::Coin<Y>) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        coin::merge(&mut metadata.balance_y, amount);
    }

    /// Mints LP tokens to a specified address
    fun mint_lp_to<X, Y>(
        to: address,
        amount: u64,
        mint_cap: &coin::MintCapability<LPToken<X, Y>>
    ) {
        let coins = coin::mint<LPToken<X, Y>>(amount, mint_cap);
        coin::deposit(to, coins);
    }

    /// Mints LP tokens and returns them (internal use)
    fun mint_lp<X, Y>(amount: u64, mint_cap: &coin::MintCapability<LPToken<X, Y>>): coin::Coin<LPToken<X, Y>> {
        coin::mint<LPToken<X, Y>>(amount, mint_cap)
    }

    /// Returns the total supply of LP tokens for a pair
    public fun total_lp_supply<X, Y>(): u128 {
        option::get_with_default(
            &coin::supply<LPToken<X, Y>>(),
            0u128
        )
    }

    /// Returns the last recorded sqrt(K) for a pool (used for fee calculation)
    public fun k_sqrt<X, Y>(pool_addr: address) : u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata<X, Y>(pool_addr, metadatas);
        metadata.k_sqrt_last
    }

    /// Returns the accumulated fee amount in LP tokens for a pool
    public fun fee_amount<X, Y>(pool_addr: address): u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata<X, Y>(pool_addr, metadatas);
        coin::value(&metadata.fee_amount)
    }

    /// Mints new LP tokens for liquidity providers based on the change in sqrt(K)
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
        // Calculate the root K for the last mint and current balances
        let root_k_sqrt = pool_math_utils::get_k_sqrt(
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x,
            reserve.reserve_virtual_y
        );
        let k_sqrt = pool_math_utils::get_k_sqrt(
            balance_x, 
            balance_y, 
            balance_virtual_x,
            balance_virtual_y
        ); 
        // Calculate the difference in K
        let k_sqrt_diff = k_sqrt - root_k_sqrt; 

        // Calculate the LP and fee amounts to mint
        let (to_lp, fee) = pool_math_utils::get_liquidity_and_fee_amount(
            k_sqrt_diff,
        );
        // Mint LP tokens and fee tokens
        let lp = mint_lp<X, Y>((to_lp as u64), &metadata.mint_cap);
        let fee_coin = mint_lp<X, Y>(fee, &metadata.mint_cap);
        coin::merge(&mut metadata.fee_amount, fee_coin);
        metadata.k_sqrt_last = k_sqrt;
        (lp, fee)
    }

    /// Adds liquidity to the pool directly, returning optimal amounts and LP tokens
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
        // Calculate optimal amounts to add based on current reserves
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

        // Extract any excess tokens and deposit the optimal amounts
        let left_x = coin::extract(&mut x, amount_x - a_x);
        let left_y = coin::extract(&mut y, amount_y - a_y);
        deposit_x<X, Y>(pool_addr, x);
        deposit_y<X, Y>(pool_addr, y);
        let (lp, fee_amount) = mint<X, Y>(pool_addr);
        (a_x, a_y, lp, fee_amount, left_x, left_y)
    }

    /// Checks if the sender has a CoinStore for type X, and registers if not
    public fun check_or_register_coin_store<X>(sender: &signer) {
        if (!coin::is_account_registered<X>(signer::address_of(sender))) {
            coin::register<X>(sender);
        };
    }

    /// Adds liquidity to the pool, mints LP tokens, and emits an event
    public fun add_liquidity<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64, u64) acquires TokenPairReserves, TokenPairMetadatas, PairEventHolder {
        // Withdraw tokens from sender and add liquidity
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

        // Emit the add liquidity event
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

    /// Sets the protocol fee recipient (admin only)
    public entry fun set_fee_to(sender: &signer, new_fee_to: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.fee_to = new_fee_to;
    }

    /// Sets the admin address (admin only)
    public entry fun set_admin(sender: &signer, new_admin: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.admin = new_admin;
    }

    /// Upgrades the swap module by publishing new code (admin only)
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

    /// Updates the reserves for a pool with new balances and timestamp
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

    /// Swaps tokens in the pool, transferring output to the recipient and emitting an event
    /// x_for_y: true means swapping X for Y, false means swapping Y for X
    /// limit_amount_calculated: slippage protection (max output allowed)
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
        let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut<X, Y>(pool_addr, metadatas);
        // Calculate output amounts using pool math
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

        // Get the actual reserves (real tokens only)
        let (actual_x, actual_y) = pool_math_utils::get_actual_x_y(
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_virtual_x, 
            reserve.reserve_virtual_y
        );
        // Handle swap direction
        if (x_for_y) {
            // Swapping X for Y
            let coin = coin::withdraw<X>(sender, amount_in);
            coin::merge(&mut metadata.balance_x, coin);
            assert!(amount_out <= actual_y, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            let coins_y_out = coin::zero<Y>();
            let virtual_coins_y_out = coin::zero<VirtualX<Y, X>>();
            coin::merge(
                &mut coins_y_out, 
                extract_y(
                    amount_out, 
                    metadata
                )
            );
            coin::merge(
                &mut virtual_coins_y_out, 
                extract_virtual_y(
                    amount_virtual_out, 
                    metadata
                )
            );
            assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            reserve.reserve_y -= amount_out;
            reserve.reserve_virtual_y -= amount_virtual_out;
            reserve.reserve_x += amount_in;
            coin::deposit(recipient_addr, coins_y_out);
            coin::deposit(recipient_addr, virtual_coins_y_out);
        } else {
            // Swapping Y for X
            let coin = coin::withdraw<Y>(sender, amount_in);
            coin::merge(&mut metadata.balance_y, coin);
            assert!(amount_out <= actual_x, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            let coins_x_out = coin::zero<X>();
            let virtual_coins_x_out = coin::zero<VirtualX<X, Y>>();
            coin::merge(
                &mut coins_x_out, 
                extract_x(
                    amount_out, 
                    metadata
                )
            );
            assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
            coin::merge(
                &mut virtual_coins_x_out, 
                extract_virtual_x(
                    amount_virtual_out, 
                    metadata
                )
            );
            reserve.reserve_x -= amount_out;
            reserve.reserve_virtual_x -= amount_virtual_out;
            reserve.reserve_y += amount_in;
            coin::deposit(recipient_addr, coins_x_out);
            coin::deposit(recipient_addr, virtual_coins_x_out);
        };

        // Emit the swap event
        emit_swap_event<X, Y>(
            signer::address_of(sender),
            pool_addr,
            amount_in,
            x_for_y,
            amount_out,
            amount_virtual_out,
            recipient_addr
        );
        (amount_out, amount_virtual_out)
    }

    /// Emits a swap event for the given parameters
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

    /// Returns the output amounts for a given input and direction, without executing the swap
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

    /// Returns the input amount required to get a desired output, for a given direction
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

    /// Asserts that a pair is created for either (X, Y) or (Y, X)
    public fun is_pair_created_internal<X, Y>(pool_addr: address) acquires TokenPairReserves {
        assert!(
            is_pair_created<X, Y>(pool_addr) || is_pair_created<Y, X>(pool_addr), 
            ERROR_PAIR_NOT_CREATED
        );
    }

    /// Asserts that a pair is not created for both (X, Y) and (Y, X)
    public fun is_pair_not_create_internal<X, Y>(pool_addr: address) acquires TokenPairReserves {
        assert!(
            !is_pair_created<X, Y>(pool_addr) && !is_pair_created<Y, X>(pool_addr), 
            ERROR_PAIR_CREATED
        );
    }

    /// Test-only function to initialize the module (for unit tests)
    #[test_only]
    public fun initialize(sender: &signer) {
        init_module(sender);
    }
}