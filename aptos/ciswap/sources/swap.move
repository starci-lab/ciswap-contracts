/// CiSwap with (X + ciX) (Y + ciY) = K
module ciswap::swap {
    // ===============================================
    //  CiSwap Swap Module
    //  ----------------------------------------------
    //  Core AMM logic for CiSwap: pool management, swaps, liquidity, fees, and events
    // ===============================================

    // This module implements the main logic for the CiSwap protocol, including pool creation, swaps, liquidity management, fee accounting, and event emission.
    // All structs, functions, and constants are commented for clarity. No code logic is changed.

    // ------------------------------------------------------------------------
    // Imports
    // ------------------------------------------------------------------------
    // Importing necessary modules from the standard library, Aptos framework, and local modules
    use std::signer::{ Self };
    use std::option::{ Self };
    use std::string::{ Self };
    use aptos_std::type_info::{ Self };
    use aptos_std::event::{ Self, EventHandle };
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::timestamp::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::code::{Self};
    use aptos_framework::table::{ Self, Table };
    use aptos_framework::fungible_asset::{ Self, FungibleStore, Metadata, FungibleAsset };
    use ciswap::pool_math_utils::{Self};
    use ciswap::package_manager::{Self};
    use ciswap::position::{ Self };
    use ciswap::fa_utils::{ Self };
    use aptos_framework::object::{ Self, Object };
    use ciswap::u64_utils::{Self};
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
    /// Represents a fungible asset balance and its associated store object.
    struct FABalance has key, store {
        balance: u64, // The balance of the token
        store: Object<FungibleStore> // The fungible store object for this balance
    }

    /// The event emitted when liquidity is added to a pool.
    /// - sender_addr: Address of the liquidity provider
    /// - pool_id: Address of the pool
    /// - amount_x: Amount of token X added
    /// - amount_y: Amount of token Y added
    /// - liquidity: Amount of LP tokens minted
    /// - fee_amount: Fee amount collected
    struct AddLiquidityEvent has drop, store {
        sender_addr: address, // Address of the liquidity provider
        pool_id: u64,   // Address of the pool
        amount_x: u64,        // Amount of token X added
        amount_y: u64,        // Amount of token Y added
        liquidity: u64,       // Amount of LP tokens minted
        lp_nft_addr: address // Address of the NFT position created
    }

    struct IncreaseLiquidityEvent has drop, store {
        sender_addr: address, // Address of the liquidity provider
        pool_id: u64,   // Address of the pool
        amount_x: u64,        // Amount of token X added
        amount_y: u64,        // Amount of token Y added
        liquidity: u64,       // Amount of LP tokens minted
        lp_nft_addr: address // Address of the NFT position created
    }

    /// The event emitted when liquidity is removed from a pool.
    /// - sender_addr: Address of the liquidity provider
    ///
    /// # Fields
    /// - `user`: Address of the user removing liquidity
    /// - `liquidity`: Amount of LP tokens burned
    /// - `amount_x`: Amount of token X withdrawn
    /// - `amount_y`: Amount of token Y withdrawn
    /// - `fee_amount`: Fee amount collected
    struct RemoveLiquidityEvent has drop, store {
        sender_addr: address, // Address of the liquidity provider
        pool_id: u64,   // Address of the pool
        amount_x: u64,        // Amount of token X withdrawn
        amount_y: u64,        // Amount of token Y withdrawn
        fee_amount: u64       // Fee amount collected
    }

    /// The event emitted when a swap occurs.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the swap initiator
    /// - `pool_index`: Address of the pool
    /// - `amount_in`: Amount of input token
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `amount_out`: Amount of output token
    /// - `amount_debt_out`: Amount of virtual output token
    /// - `recipient_addr`: Address receiving the output
    struct SwapEvent has drop, store {
        sender_addr: address,     // Address of the swap initiator
        pool_id: u64,             // Address of the pool
        amount_in: u64,           // Amount of input token
        x_for_y: bool,            // Direction of swap (true if X for Y)
        amount_out: u64,          // Amount of output token
        amount_debt_out: u64,  // Amount of virtual output token
        recipient_addr: address,  // Address receiving the output
    }

    /// The event emitted when virtual tokens are redeemed for real tokens.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the redeemer
    /// - `pool_index`: Address of the pool
    /// - `amount_debt_x`: Amount of virtual X redeemed
    /// - `amount_debt_y`: Amount of virtual Y redeemed
    /// - `redeemed_amount_x`: Amount of real X received
    /// - `redeemed_amount_y`: Amount of real Y received
    /// - `recipient_addr`: Address receiving the real tokens
    struct RedeemEvent has drop, store {
        sender_addr: address,         // Address of the redeemer
        pool_id: u64,              // Address of the pool
        amount_debt_x: u64,        // Amount of virtual X redeemed
        amount_debt_y: u64,        // Amount of virtual Y redeemed
        redeemed_amount_x: u64,       // Amount of real X received
        redeemed_amount_y: u64,       // Amount of real Y received
        recipient_addr: address       // Address receiving the real tokens
    }

    struct CollectFeesEvent has drop, store {
        sender_addr: address, // Address of the fee collector
        pool_id: u64,          // Address of the pool
        nft_addr: address, // Address of the NFT position
        amount_x: u64,
        amount_y: u64,
        amount_debt_x: u64,
        amount_debt_y: u64
    }

    struct CollectProtocolEvent has drop, store {
        sender_addr: address, // Address of the fee collector
        pool_id: u64,          // Address of the pool
        amount_x: u64,
        amount_y: u64,
        amount_debt_x: u64,
        amount_debt_y: u64
    }

    /// Holds all event handles for a pair (add/remove liquidity, swap, redeem).
    ///
    /// # Fields
    /// - `add_liquidity`: Event handle for AddLiquidityEvent
    /// - `remove_liquidity`: Event handle for RemoveLiquidityEvent
    /// - `swap`: Event handle for SwapEvent
    /// - `redeem`: Event handle for RedeemEvent
    struct PairEventHolder has key {
        pair_created: EventHandle<PairCreatedEvent>,
        add_liquidity: EventHandle<AddLiquidityEvent>,
        increase_liquidity: EventHandle<IncreaseLiquidityEvent>,
        remove_liquidity: EventHandle<RemoveLiquidityEvent>,
        swap: EventHandle<SwapEvent>,
        redeem: EventHandle<RedeemEvent>,
        collect_fees: EventHandle<CollectFeesEvent>,
        collect_protocol: EventHandle<CollectProtocolEvent>
    }

    /// Stores metadata for a token pair, including balances and capabilities.
    ///
    /// # Fields
    /// - `creator`: Creator/admin of the pair
    /// - `fee_amount`: Accumulated fees in LP tokens
    /// - `k_sqrt_last`: Last recorded sqrt(K) for fee calculation
    /// - `balance_x`: Pool balance of token X
    /// - `balance_y`: Pool balance of token Y
    /// - `balance_debt_x`: Virtual X balance
    /// - `balance_debt_y`: Virtual Y balance
    /// - `balance_locked_lp`: Locked LP tokens (minimum liquidity)
    /// - `mint_cap`, `burn_cap`, `freeze_cap`: Capabilities for LP tokens
    /// - `mint_debt_x_cap`, `burn_debt_x_cap`, `freeze_debt_x_cap`: Capabilities for virtual X
    /// - `mint_debt_y_cap`, `burn_debt_y_cap`, `freeze_debt_y_cap`: Capabilities for virtual Y
    struct TokenPairMetadata has key, store {
        creator: address, // Address of the user who created the pair (admin for this pair)
        k_sqrt_last: u64, // Last recorded sqrt(K) for fee calculation (used for fee distribution)
        k_sqrt_locked: u64, // Last recorded sqrt(K) for locked liquidity
        store_x: Object<FungibleStore>, // Pool's current balance of token X
        store_y: Object<FungibleStore>, // Pool's current balance of token Y
        store_fee_x: Object<FungibleStore>, // Accumulated fees in token X
        store_fee_y: Object<FungibleStore>, // Accumulated fees in token Y
        store_fee_debt_x: Object<FungibleStore>, // Accumulated fees in virtual X
        store_fee_debt_y: Object<FungibleStore>, // Accumulated fees in virtual Y
        store_protocol_fee_x: Object<FungibleStore>, // Accumulated protocol fees in token X
        store_protocol_fee_y: Object<FungibleStore>, // Accumulated protocol fees in token Y
        store_protocol_fee_debt_x: Object<FungibleStore>, // Accumulated protocol fees in virtual X
        store_protocol_fee_debt_y: Object<FungibleStore>, // Accumulated protocol fees in virtual Y
        global_x_fee_growth_x128: u128, // Global fee growth for the pair (used for fee distribution)
        global_y_fee_growth_x128: u128, // Global fee growth for the pair (used for fee distribution)
        global_debt_x_fee_growth_x128: u128, // Global fee growth for virtual X (used for fee distribution)
        global_debt_y_fee_growth_x128: u128, // Global fee growth for virtual Y (used for fee distribution)
        store_debt_x: Object<FungibleStore>, // Pool's current balance of virtual X
        store_debt_y: Object<FungibleStore>, // Pool's current balance of virtual Y
    }

    /// Table of all TokenPairMetadata for a given pair type.
    ///
    /// # Fields
    /// - `metadatas`: Table mapping pool address to TokenPairMetadata
    struct TokenPairMetadatas has key, store {
        metadatas: Table<u64, TokenPairMetadata>, // Mapping pool address to metadata
    }

    /// Reserve information for a token pair (real and virtual reserves).
    ///
    /// # Fields
    /// - `reserve_x`: Real reserve of token X
    /// - `reserve_y`: Real reserve of token Y
    /// - `reserve_debt_x`: Virtual reserve of X
    /// - `reserve_debt_y`: Virtual reserve of Y
    /// - `block_timestamp_last`: Last update timestamp
    struct TokenPairReserve has key, store {
        reserve_x: u64, // Real reserve of token X
        reserve_y: u64, // Real reserve of token Y
        reserve_debt_x: u64, // Virtual reserve of X
        reserve_debt_y: u64, // Virtual reserve of Y
        block_timestamp_last: u64 // Last update timestamp (seconds)
    }

    /// Table of all TokenPairReserve for a given pair type.
    ///
    /// # Fields
    /// - `reserves`: Table mapping pool address to TokenPairReserve
    struct TokenPairReserves has key, store {
        reserves: Table<u64, TokenPairReserve>, // Mapping pool address to reserves
    }

    /// Main module resource, stores admin, fee info, and event handle for pair creation.
    ///
    /// # Fields
    /// - `signer_cap`: Capability to sign as resource account
    /// - `fee_to`: Address to receive protocol fees
    /// - `pool_creation_fee_apt`: Accumulated fees in APT
    /// - `admin`: Admin address
    /// - `creation_fee_in_apt`: Fee for creating a new pair
    /// - `pair_created`: Event handle for pair creation
    struct SwapInfo has key {
        fee_to: address, // Address to receive protocol fees
        pool_creation_fee_apt: coin::Coin<AptosCoin>, // Accumulated fees in APT
        admin: address, // Admin address
        creation_fee_in_apt: u64, // Fee for creating a new pair
        next_pool_id: u64, // Id of the next pool to be created
        pair_created: event::EventHandle<PairCreatedEvent> // Event handle for pair creation
    }

    // ------------------------------------------------------------------------
    // Error Codes
    // ------------------------------------------------------------------------
    // Error codes for various failure conditions
    const ERR_ALREADY_INITIALIZED: u64 = 1; // Pair already initialized
    const ERR_NOT_ADMIN: u64 = 2; // Not admin
    const ERR_REDEMPTION_NOT_ENOUGH: u64 = 3; // Not enough tokens to redeem
    const ERR_TOKEN_A_NOT_ZERO: u64 = 4; // Token A balance not zero
    const ERR_TOKEN_B_NOT_ZERO: u64 = 5; // Token B balance not zero
    const ERR_TOKEN_NOT_SORTED: u64 = 6; // Token types not sorted
    const ERR_INSUFFICIENT_AMOUNT: u64 = 7; // Insufficient amount
    const ERR_INVALID_AMOUNT: u64 = 8; // Invalid amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 9; // Insufficient liquidity
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 10; // Insufficient input amount
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 11; // Insufficient output amount
    const ERR_INSUFFICIENT_DEBT_OUTPUT_AMOUNT: u64 = 11; // Insufficient debt output amount
    const ERR_POOL_NOT_CREATED: u64 = 12; // Pair not created
    const ERR_POOL_CREATED: u64 = 13; // Pair already created
    const ERR_INSUFFICIENT_INPUT_BALANCE: u64 = 14; // Insufficient input balance

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    /// Event emitted when a new pair is created.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the creator
    /// - `pool_index`: Address of the new pool
    /// - `token_x`: Name of token X
    /// - `token_y`: Name of token Y
    /// - `debt_token_x`: Name of virtual token X
    /// - `balance_debt_token_x`: Initial virtual X balance
    /// - `debt_token_y`: Name of virtual token Y
    /// - `balance_debt_token_y`: Initial virtual Y balance
    struct PairCreatedEvent has drop, store {
        sender_addr: address, // Address of the creator
        pool_id: u64, // Index of the pool in the pair
        address_x: address, // Address of token X
        address_y: address, // Address of token Y
        address_debt_x: address, // Name of virtual token X
        address_debt_y: address, // Name of virtual token Y
        amount_debt_x: u64,    // Initial virtual X balance
        amount_debt_y: u64,     // Initial virtual Y balance
        collection_addr: address // Address of the LP token collection
    }

    // ------------------------------------------------------------------------
    // Core Methods
    // ------------------------------------------------------------------------

    /// Initializes the module by creating the SwapInfo resource in the resource account.
    ///
    /// Parameters:
    /// - sender: The deployer signer
    ///
    /// Effects:
    /// - Creates the SwapInfo resource in the resource account
    /// - Sets up admin, fee recipient, and event handle
    fun init_module(_: &signer) {
        // Store SwapInfo in the resource account
        let resource_signer = package_manager::get_resource_signer();
        // Initialize the position module
        move_to(&resource_signer, SwapInfo {
            fee_to: DEFAULT_FEE_TO,
            pool_creation_fee_apt: coin::zero<AptosCoin>(),
            creation_fee_in_apt: CREATION_FEE_IN_APT,
            admin: DEFAULT_ADMIN,
            next_pool_id: 0, // Initialize next pool id to 0
            pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
        });
        // Initialize empty tables for token pair metadata and reserves
        move_to(&resource_signer, TokenPairMetadatas {
            metadatas: table::new<u64, TokenPairMetadata>(), // Initialize empty metadata table
        });
        // Initialize empty reserves table
        move_to(&resource_signer, TokenPairReserves {
            reserves: table::new<u64, TokenPairReserve>(), // Initialize empty reserves table
        });
        // Initialize event holder
        move_to<PairEventHolder>(
            &resource_signer,
            PairEventHolder {
                pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
                add_liquidity: account::new_event_handle<AddLiquidityEvent>(&resource_signer),
                remove_liquidity: account::new_event_handle<RemoveLiquidityEvent>(&resource_signer),
                swap: account::new_event_handle<SwapEvent>(&resource_signer),
                redeem: account::new_event_handle<RedeemEvent>(&resource_signer),
                collect_fees: account::new_event_handle<CollectFeesEvent>(&resource_signer),
                collect_protocol: account::new_event_handle<CollectProtocolEvent>(&resource_signer),
                increase_liquidity: account::new_event_handle<IncreaseLiquidityEvent>(&resource_signer),
            }
        );
    }

    /// Creates a new token pair pool with specified virtual balances.
    ///
    /// Parameters:
    /// - sender: The signer creating the pair
    /// - address_x: Address of token X
    /// - address_y: Address of token Y
    /// - amount_debt_x: Initial virtual X liquidity
    /// - amount_debt_y: Initial virtual Y liquidity
    ///
    /// Effects:
    /// - Checks that the pair is not already created
    /// - Transfers creation fee
    /// - Initializes LP and virtual tokens
    /// - Stores metadata and reserves
    /// - Emits PairCreatedEvent
    public fun create_pair(
        sender: &signer,
        address_x: address, // Address of token X
        address_y: address, // Address of token Y
        amount_debt_x: u64, // Initial virtual X liquidity
        amount_debt_y: u64  // Initial virtual Y liquidity
    ) acquires 
        SwapInfo, 
        PairEventHolder, 
        TokenPairMetadatas, 
        TokenPairReserves
    {
        // --------------------------------------------------------------------
        // 1. Check that the pair is not already initialized
        let resource_signer = package_manager::get_resource_signer();
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);

        // --------------------------------------------------------------------
        // 2. Transfer the creation fee in APT to the resource account
        let pool_id = swap_info.next_pool_id;
        let creation_fee = coin::withdraw<AptosCoin>(sender, swap_info.creation_fee_in_apt);
        coin::merge(&mut swap_info.pool_creation_fee_apt, creation_fee);

        // --------------------------------------------------------------------
        // 3. Create the LP token for the pair
        let collection_addr = position::create_collection(
            pool_id
        );
        // --------------------------------------------------------------------
        // 4. Create and register the virtual token X
        let name_debt_x: string::String = string::utf8(b"ci");
        let name = fungible_asset::name(
            fa_utils::get_metadata(address_x)
        );
        string::append(
            &mut name_debt_x, 
            name
        );
        let symbol_debt_x: string::String = string::utf8(b"ci");
        let symbol = fungible_asset::symbol(
            fa_utils::get_metadata(address_x)
        );
        string::append(
            &mut symbol_debt_x, 
            symbol
        );

        let salt_x = string::utf8(b"x-");
        string::append(
            &mut salt_x, 
            u64_utils::u64_to_string(pool_id)
        );
        // Create the virtual token X
        let address_debt_x = fa_utils::create_fungible_asset(
            &resource_signer,
            *string::bytes(&salt_x),
            name,
            symbol,
            fungible_asset::icon_uri(
                fa_utils::get_metadata(address_x)
            ),
            fungible_asset::project_uri(
                fa_utils::get_metadata(address_x)
            )
        );
        // Mint the initial virtual X tokens to the resource account
        let fa_debt_x = fa_utils::mint(
            address_debt_x,
            amount_debt_x,
        );
        let store_debt_x = fa_utils::create_store(
            &resource_signer,
            address_debt_x
        );
        // Deposit the virtual X tokens into the resource account
        fungible_asset::deposit(
            store_debt_x,
            fa_debt_x
        );
        
        let name_debt_y: string::String = string::utf8(b"ci");
        let name = fungible_asset::name(
            fa_utils::get_metadata(address_y)
        );
        string::append(
            &mut name_debt_y, 
            name
        );
        let symbol_debt_y: string::String = string::utf8(b"ci");
        let symbol = fungible_asset::symbol(
            fa_utils::get_metadata(address_y)
        );
        string::append(
            &mut symbol_debt_y, 
            symbol
        );

        let salt_y = string::utf8(b"y-");
        string::append(
            &mut salt_y, 
            u64_utils::u64_to_string(pool_id)
        );
        // Create the virtual token X
        let address_debt_y = fa_utils::create_fungible_asset(
            &resource_signer,
            *string::bytes(&salt_y),
            name,
            symbol,
            fungible_asset::icon_uri(
                fa_utils::get_metadata(address_y)
            ),
            fungible_asset::project_uri(
                fa_utils::get_metadata(address_y)
            )
        );
        // Mint the initial virtual Y tokens to the resource account
        let fa_debt_y = fa_utils::mint(
            address_debt_y,
            amount_debt_y,
        );
        let store_debt_y = fa_utils::create_store(
            &resource_signer,
            address_debt_y
        );
        // Deposit the virtual Y tokens into the resource account
        fungible_asset::deposit(
            store_debt_y,
            fa_debt_y
        );

        let locked_liquidity = pool_math_utils::calculate_locked_liquidity(
            amount_debt_x,
            amount_debt_y
        );

        // Add the new pair's metadata to the table
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        table::add(
            &mut metadatas.metadatas,
            pool_id, // Pool id is the address of the pool
            TokenPairMetadata {  
                creator: sender_addr, // Address of the user who created the pair (admin for this pair)
                k_sqrt_locked: locked_liquidity,
                k_sqrt_last: locked_liquidity, // Last recorded sqrt(K) for fee calculation (used for fee distribution)
                store_fee_x: fa_utils::create_store(
                    &resource_signer,
                    address_x
                ), // Store for accumulated fees in token X
                store_fee_y: fa_utils::create_store(
                    &resource_signer,
                    address_y
                ), // Store for accumulated fees in token X
                store_x: fa_utils::create_store(
                    &resource_signer,
                    address_x
                ), // Store for accumulated fees in token X
                store_y: fa_utils::create_store(
                    &resource_signer,
                    address_y
                ), // Store for accumulated fees in token X
                store_debt_x, // Store for accumulated fees in token X
                store_debt_y, // Store for accumulated fees in token X
                store_fee_debt_x: fa_utils::create_store(
                    &resource_signer,
                    address_debt_x // Fixed: was using address_debt_y for debt_x store
                ), // Store for accumulated fees in virtual X
                store_fee_debt_y: fa_utils::create_store(
                    &resource_signer,
                    address_debt_y
                ), // Store for accumulated fees in virtual Y
                store_protocol_fee_x: fa_utils::create_store(
                    &resource_signer,
                    address_x
                ), // Store for accumulated protocol fees in token X
                store_protocol_fee_y: fa_utils::create_store(
                    &resource_signer,
                    address_y
                ), // Store for accumulated protocol fees in token Y
                store_protocol_fee_debt_x: fa_utils::create_store(
                    &resource_signer,
                    address_debt_x
                ), // Store for accumulated protocol fees in virtual X
                store_protocol_fee_debt_y: fa_utils::create_store(
                    &resource_signer,
                    address_debt_y
                ), // Store for accumulated protocol fees in virtual Y
                global_x_fee_growth_x128: 0, // Global fee growth for the pair (used for fee distribution)
                global_y_fee_growth_x128: 0, // Global fee growth for the pair (used for fee distribution)
                global_debt_y_fee_growth_x128: 0, // Global fee growth for virtual Y (
                global_debt_x_fee_growth_x128: 0, // Global fee growth for virtual X (
            }
        );  
        
        // --------------------------------------------------------------------
        // Add the new pair's reserves to the table
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let block_timestamp_last = timestamp::now_seconds();
        table::add(
            &mut reserves.reserves,
            pool_id,
            TokenPairReserve {
                reserve_x: 0,
                reserve_y: 0,
                reserve_debt_x: amount_debt_x,
                reserve_debt_y: amount_debt_y,
                block_timestamp_last
            }
        );

        swap_info.next_pool_id = pool_id + 1; // Increment the next pool id for future pairs

        let pair_event_holder = borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT);
        event::emit_event<PairCreatedEvent>(
            &mut pair_event_holder.pair_created,
            PairCreatedEvent {
                sender_addr,
                pool_id,
                address_x,
                address_y,
                address_debt_x,
                address_debt_y,
                amount_debt_x,
                amount_debt_y,
                collection_addr
            }
        );
    }

    /// Returns the current balances of X, Y, virtual X, and virtual Y in the pool.
    ///
    /// Parameters:
    /// - pool_id: The pool identifier
    ///
    /// Returns:
    /// - (u64, u64, u64, u64): Balances of X, Y, virtual X, and virtual Y
    public fun token_balances(pool_id: u64): (u64, u64, u64, u64) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        (
            fungible_asset::balance(metadata.store_x),
            fungible_asset::balance(metadata.store_y), // Fixed: was using store_x instead of store_y
            fungible_asset::balance(metadata.store_debt_x),
            fungible_asset::balance(metadata.store_debt_y)
        )
    }

    /// Returns a reference to the metadata for a given pool address.
    ///
    /// Parameters:
    /// - pool_id: The pool identifier
    /// - metadatas: Reference to the TokenPairMetadatas resource
    ///
    /// Returns:
    /// - &TokenPairMetadata: Reference to the pool's metadata
    public fun get_metadata(
        pool_id: u64, 
        metadatas: &mut TokenPairMetadatas
    ): &TokenPairMetadata {
        table::borrow(&mut metadatas.metadatas, pool_id)  
    }

    /// Returns a mutable reference to the metadata for a given pool address.
    ///
    /// Parameters:
    /// - pool_index: The pool identifier
    /// - metadatas: Mutable reference to the TokenPairMetadatas resource
    ///
    /// Returns:
    /// - &mut TokenPairMetadata: Mutable reference to the pool's metadata
    public fun get_metadata_mut(
        pool_index: u64, 
        metadatas: &mut TokenPairMetadatas
    ): &mut TokenPairMetadata {
        table::borrow_mut(&mut metadatas.metadatas, pool_index)  
    }

    /// Returns a reference to the reserves for a given pool address.
    ///
    /// Parameters:
    /// - pool_id: The pool identifier
    /// - reserves: Reference to the TokenPairReserves resource
    ///
    /// Returns:
    /// - &TokenPairReserve: Reference to the pool's reserves
    public fun get_reserve(
        pool_id: u64,
        reserves: &mut TokenPairReserves
    ): &TokenPairReserve {
        table::borrow(&mut reserves.reserves, pool_id)  
    }

    /// Returns a mutable reference to the reserves for a given pool address.
    ///
    /// Parameters:
    /// - pool_index: The pool identifier
    /// - reserves: Mutable reference to the TokenPairReserves resource
    ///
    /// Returns:
    /// - &mut TokenPairReserve: Mutable reference to the pool's reserves
    public fun get_reserve_mut(
        pool_index: u64,
        reserves: &mut TokenPairReserves
    ): &mut TokenPairReserve {
        table::borrow_mut(&mut reserves.reserves, pool_index)  
    }

    /// Redeems virtual tokens for real tokens, transferring them to the recipient
    public fun redeem(
        sender: &signer,
        pool_id: u64,
        amount_debt_x: u64,
        amount_debt_y: u64,
        recipient_addr: address
    ): (
        u64, 
        u64
    ) acquires TokenPairMetadatas, TokenPairReserves, PairEventHolder {
        // Get references to metadata and reserves
        let sender_addr = signer::address_of(sender);
        let resource_signer = package_manager::get_resource_signer();
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut(pool_id, metadatas);
        let reserve = get_reserve_mut(pool_id, reserves);
        // Ensure the amounts are valid
        let redeemed_amount_x = pool_math_utils::get_redeemed_amount(amount_debt_x);
        let redeemed_amount_y = pool_math_utils::get_redeemed_amount(amount_debt_y);
        // Ensure the pool has enough real tokens to redeem
        assert!(
            fungible_asset::balance(metadata.store_debt_x) >= redeemed_amount_x, 
            ERR_REDEMPTION_NOT_ENOUGH
        );
        assert!(
            fungible_asset::balance(metadata.store_debt_y) >= redeemed_amount_y, 
            ERR_REDEMPTION_NOT_ENOUGH
        );
        // Burn the debt tokens from the sender
        fa_utils::burn_from_primary_store(
            signer::address_of(sender),
            fa_utils::get_address_from_store(metadata.store_debt_x),
            amount_debt_x,
        );
        fa_utils::burn_from_primary_store(
            signer::address_of(sender),
            fa_utils::get_address_from_store(metadata.store_debt_y),
            amount_debt_y,
        );
        // Mint new virtual tokens to the pool to maintain liquidity
        let redeemed_debt_x = fa_utils::mint(
            fa_utils::get_address_from_store(metadata.store_debt_x),
            amount_debt_x
        );
        let redeemed_y = fa_utils::mint(
            fa_utils::get_address_from_store(metadata.store_debt_y),
            amount_debt_y
        );
        fungible_asset::deposit(
            metadata.store_debt_x,
            redeemed_debt_x
        );
        fungible_asset::deposit(
            metadata.store_debt_y,
            redeemed_y
        );
        // Extract real tokens from the pool and deposit to recipient
        let fa_x = fungible_asset::withdraw(
            &resource_signer,
            metadata.store_debt_x, 
            redeemed_amount_x
        );
        let fa_y = fungible_asset::withdraw(
            &resource_signer,
            metadata.store_debt_y, 
            redeemed_amount_y
        );
        fa_utils::deposit(
            recipient_addr,
            fa_x
        );
        fa_utils::deposit(
            recipient_addr,
            fa_y
        );
        // Emit the redeem event
        event::emit_event<RedeemEvent>(
            &mut borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT).redeem,
            RedeemEvent {
                sender_addr,
                pool_id,
                amount_debt_x,
                amount_debt_y,
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
    public fun token_reserves(
        pool_index: u64
    ): (
        u64, 
        u64, 
        u64,
        u64
    ) acquires TokenPairReserves {
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve(pool_index, reserves);
        (
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_debt_x, 
            reserve.reserve_debt_y
        )
    }   

    /// Returns the last recorded sqrt(K) for a pool (used for fee calculation)
    public fun k_sqrt_last(pool_id: u64) : u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        metadata.k_sqrt_last
    }

    /// Adds liquidity to the pool directly, returning optimal amounts and LP tokens
    fun add_liquidity_core(
        sender: &signer,
        pool_id: u64,
        amount_x: u64,
        amount_y: u64,
    ): (
        u64, 
        u64, 
        u64, // k difference
    ) acquires TokenPairReserves, TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut(pool_id, metadatas);
        let (
            reserve_x, 
            reserve_y, 
            reserve_debt_x, 
            reserve_debt_y
        ) = token_reserves(pool_id);
        // Calculate optimal amounts to add based on current reserves
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve_mut(pool_id, reserves);
        let (desired_x, desired_y) = {
            let amount_y_optimal = pool_math_utils::quote(
                amount_x, 
                reserve_x, 
                reserve_y, 
                reserve_debt_x,
                reserve_debt_y
                );
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal = pool_math_utils::quote(
                    amount_y, 
                    reserve_y,
                    reserve_x,
                    reserve_debt_y,
                    reserve_debt_x
                );
                assert!(amount_x_optimal <= amount_x, ERR_INVALID_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        assert!(desired_x <= amount_x, ERR_INSUFFICIENT_AMOUNT);
        assert!(desired_y <= amount_y, ERR_INSUFFICIENT_AMOUNT);

        // Extract any excess tokens and deposit the optimal amounts
        let desired_x_fa = fa_utils::withdraw_fa_from_address(
            sender,
            fa_utils::get_address_from_store(
                metadata.store_x
            ),
            desired_x);
        let desired_y_fa = fa_utils::withdraw_fa_from_address(
            sender,
            fa_utils::get_address_from_store(
                metadata.store_y
            ),
            desired_y);

        fungible_asset::deposit(
            metadata.store_x,
            desired_x_fa
        );
        fungible_asset::deposit(
            metadata.store_y,
            desired_y_fa
        );

        let updated_reserve_x = reserve_x + desired_x;
        let updated_reserve_y = reserve_y + desired_y;

        let updated_k_sqrt = pool_math_utils::get_k_sqrt(
            updated_reserve_x, 
            updated_reserve_y, 
            reserve_debt_x,
            reserve_debt_y
        );
        let k_diff = updated_k_sqrt - metadata.k_sqrt_last;
        // update the metadata
        metadata.k_sqrt_last = updated_k_sqrt;    
        // update the pool's reserves
        update(
            updated_reserve_x, 
            updated_reserve_y, 
            reserve_debt_x, 
            reserve_debt_y,
            reserve
        );

        (desired_x, desired_y, k_diff)
    }

    public fun add_liquidity(
        sender: &signer,
        pool_id: u64,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64) {
        let (desired_x, desired_y, k_diff) = add_liquidity_core(
            sender,
            pool_id,
            amount_x,
            amount_y
        );
        // create a NFT LP representing the liquidity added 
        let lp_nft_addr = position::create_then_transfer_lp_nft(
            sender,
            pool_id,
            k_diff
        );
        // Emit the AddLiquidity event
        event::emit_event<AddLiquidityEvent>(
            &mut borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT).add_liquidity,
            AddLiquidityEvent {
                sender_addr: signer::address_of(sender),
                pool_id,
                amount_x: desired_x,
                amount_y: desired_y,
                liquidity: k_diff,
                lp_nft_addr
            }
        );
        (desired_x, desired_y)
    }

    public fun increase_liquidity(
        sender: &signer,
        pool_id: u64,
        amount_x: u64,
        amount_y: u64,
        lp_nft_addr: address
    ): (u64, u64) {
        let (desired_x, desired_y, k_diff) = add_liquidity_core(
            sender,
            pool_id,
            amount_x,
            amount_y
        );
        // create a NFT LP representing the liquidity added 
        position::increase_lp_nft(
            sender,
            pool_id,
            lp_nft_addr,
            k_diff,
        );
        // Emit the AddLiquidity event
        event::emit_event<IncreaseLiquidityEvent>(
            &mut borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT).increase_liquidity,
            IncreaseLiquidityEvent {
                sender_addr: signer::address_of(sender),
                pool_id,
                amount_x: desired_x,
                amount_y: desired_y,
                liquidity: k_diff,
                lp_nft_addr
            }
        );
        (desired_x, desired_y)
    }

    /// Checks if the sender has a CoinStore for type X, and registers if not
    public fun check_or_register_coin_store<X>(sender: &signer) {
        if (!coin::is_account_registered<X>(signer::address_of(sender))) {
            coin::register<X>(sender);
        };
    }

    /// Sets the admin address (admin only)
    public entry fun set_admin(sender: &signer, new_admin: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERR_NOT_ADMIN);
        swap_info.admin = new_admin;
    }

    /// Upgrades the swap module by publishing new code (admin only)
    public entry fun upgrade_swap(
        sender: &signer, 
        metadata_serialized: vector<u8>, 
        code: vector<vector<u8>>
    ) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let resource_signer = package_manager::get_resource_signer();
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERR_NOT_ADMIN);
        code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    // Updates the reserves for a pool with new balances and timestamp
    // Includes safety checks to prevent overflow/underflow
    fun update(
        balance_x: u64, 
        balance_y: u64, 
        balance_debt_x: u64, 
        balance_debt_y: u64,
        reserve: &mut TokenPairReserve
    ) {
        let block_timestamp = timestamp::now_seconds();
        // Safety check: ensure timestamp is not moving backwards
        assert!(block_timestamp >= reserve.block_timestamp_last, ERR_INVALID_AMOUNT);
        
        reserve.reserve_x = balance_x;
        reserve.reserve_y = balance_y;
        reserve.reserve_debt_x = balance_debt_x;
        reserve.reserve_debt_y = balance_debt_y;
        reserve.block_timestamp_last = block_timestamp;
    }

    /// Updates global fee growth tracking for LP positions
    /// Uses fixed-point arithmetic with scaling factor to prevent precision loss
    const SCALING_FACTOR: u128 = 18446744073709551616; // 2^64
    fun update_fees_global(
        fee_x: u64, 
        fee_y: u64,
        fee_debt_x: u64,
        fee_debt_y: u64,
        k_sqrt_diff: u64,
        metadata: &mut TokenPairMetadata
    ) {
        // Safety check: prevent division by zero
        assert!(k_sqrt_diff > 0, ERR_INVALID_AMOUNT);
        
        // Update fee growth using scaled arithmetic to maintain precision
        metadata.global_x_fee_growth_x128 += (((fee_x as u128) * SCALING_FACTOR) / (k_sqrt_diff as u128));
        metadata.global_y_fee_growth_x128 += (((fee_y as u128) * SCALING_FACTOR) / (k_sqrt_diff as u128));
        metadata.global_debt_x_fee_growth_x128 += (((fee_debt_x as u128) * SCALING_FACTOR) / (k_sqrt_diff as u128));
        metadata.global_debt_y_fee_growth_x128 += (((fee_debt_y as u128) * SCALING_FACTOR) / (k_sqrt_diff as u128));
    }

    public fun get_amount_out(
        pool_id: u64,
        amount_in: u64, 
        x_for_y: bool, 
    ): (u64, u64) acquires TokenPairReserves {
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve(pool_id, reserves);
        let (amount_out, debt_out, _, _, _, _, _) = pool_math_utils::get_amount_out(
            amount_in, 
            x_for_y, 
            reserve.reserve_x, 
            reserve.reserve_y,
            reserve.reserve_debt_x,
            reserve.reserve_debt_y
        );
        (amount_out, debt_out)
    }

    public fun get_amount_in(
        pool_id: u64,
        amount_out: u64, 
        x_for_y: bool, 
    ): (u64) acquires TokenPairReserves {
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve(pool_id, reserves);
        pool_math_utils::get_amount_in(
            amount_out, 
            x_for_y, 
            reserve.reserve_x, 
            reserve.reserve_y,
            reserve.reserve_debt_x,
            reserve.reserve_debt_y
        )
    }

    /// Swaps tokens in the pool, transferring output to the recipient and emitting an event
    /// x_for_y: true means swapping X for Y, false means swapping Y for X
    /// limit_amount_calculated: slippage protection (max output allowed)
    /// limit_debt_amount_calculated: slippage protection for debt tokens
    public fun swap(
        sender: &signer,
        pool_id: u64,
        amount_in: u64,
        x_for_y: bool,
        recipient_addr: address,
        limit_amount_calculated: u64,
        limit_debt_amount_calculated: u64
    ): (u64, u64) acquires PairEventHolder, TokenPairMetadatas, TokenPairReserves {
        // Input validation - ensure non-zero input amount
        assert!(amount_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        let resource_signer = package_manager::get_resource_signer();

        // Get mutable references to pool reserves and metadata
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve_mut(pool_id, reserves);
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut(pool_id, metadatas);
        
        // Calculate output amounts using AMM formula: (X + ciX) * (Y + ciY) = K
        let (
            amount_out, 
            amount_debt_out,
            amount_fee_out,
            amount_debt_fee_out,
            k_sqrt_diff,
            amount_out_raw,
            amount_debt_out_raw
        ) = pool_math_utils::get_amount_out(
            amount_in, 
            x_for_y, 
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_debt_x, 
            reserve.reserve_debt_y
        );
        
        // Slippage protection - ensure output meets minimum requirements
        assert!(amount_out >= limit_amount_calculated, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        assert!(amount_debt_out >= limit_debt_amount_calculated, ERR_INSUFFICIENT_DEBT_OUTPUT_AMOUNT);
        
        // Get token addresses for balance checks and transfers
        let address_fa_x = fa_utils::get_address_from_store(metadata.store_x);
        let address_fa_y = fa_utils::get_address_from_store(metadata.store_y);
        let address_fa_debt_x = fa_utils::get_address_from_store(metadata.store_debt_x);
        let address_fa_debt_y = fa_utils::get_address_from_store(metadata.store_debt_y);

        if (x_for_y) {
            // ====== SWAPPING X FOR Y ======
            // Verify sender has enough X tokens
            assert!(
                fa_utils::balance_of(signer::address_of(sender), address_fa_x) >= amount_in,
                ERR_INSUFFICIENT_INPUT_BALANCE
            );

            // Transfer input tokens from sender to pool
            let fa_x_in = fa_utils::withdraw_fa_from_address(
                sender,
                address_fa_x,
                amount_in
            );
            fungible_asset::deposit(metadata.store_x, fa_x_in);

            let amount_fee_out_rest = amount_fee_out;
            let amount_fee_debt_out_rest = amount_debt_fee_out;

            if (amount_out > 0) {
                // Transfer output tokens (Y) from pool to recipient
                let fa_y_out = fungible_asset::withdraw(
                    &resource_signer, 
                    metadata.store_y,
                    amount_out
                );
                fa_utils::deposit(
                    recipient_addr, 
                    fa_y_out
                );    
                // Process fees for Y tokens - split between LP fees and protocol fees
                let fa_y_fee_out = fungible_asset::withdraw(
                    &resource_signer,
                    metadata.store_y,
                    amount_fee_out
                );
                let (amount_protocol_fee_out, _) = pool_math_utils::get_extracted_fees(
                    amount_fee_out
                );
                // Safety check: prevent underflow
                assert!(amount_protocol_fee_out <= amount_fee_out, ERR_INVALID_AMOUNT);
                amount_fee_out_rest = amount_fee_out - amount_protocol_fee_out; // Fixed: prevent underflow
                let fa_y_protocol_fee_out = fungible_asset::extract(
                    &mut fa_y_fee_out,
                    amount_protocol_fee_out
                );
                // Deposit LP fees to fee store
                fungible_asset::deposit(
                    metadata.store_fee_y,
                    fa_y_fee_out
                );
                // Deposit protocol fees to protocol fee store
                fungible_asset::deposit(
                    metadata.store_protocol_fee_y,
                    fa_y_protocol_fee_out
                );
            };

            if (amount_debt_out > 0) {
                // Transfer debt tokens (ciY) from pool to recipient
                let fa_debt_y_out = fungible_asset::withdraw(
                    &resource_signer, 
                    metadata.store_debt_y,
                    amount_debt_out
                );
                fa_utils::deposit(
                    recipient_addr, 
                    fa_debt_y_out
                );
                // Process fees for debt Y tokens - split between LP fees and protocol fees
                let fa_y_debt_fee_out = fungible_asset::withdraw(
                    &resource_signer,
                    metadata.store_debt_y,
                    amount_debt_fee_out
                );
                let (amount_protocol_debt_fee_out, _) = pool_math_utils::get_extracted_fees(
                    amount_debt_fee_out
                );
                // Safety check: prevent underflow
                assert!(amount_protocol_debt_fee_out <= amount_debt_fee_out, ERR_INVALID_AMOUNT);
                amount_fee_debt_out_rest = amount_debt_fee_out - amount_protocol_debt_fee_out; // Fixed: prevent underflow

                let fa_y_protocol_debt_fee_out = fungible_asset::extract(
                    &mut fa_y_debt_fee_out,
                    amount_protocol_debt_fee_out
                );
                // Deposit LP debt fees to debt fee store
                fungible_asset::deposit(
                    metadata.store_fee_debt_y,
                    fa_y_debt_fee_out
                );
                // Deposit protocol debt fees to protocol debt fee store
                fungible_asset::deposit(
                    metadata.store_protocol_fee_debt_y,
                    fa_y_protocol_debt_fee_out
                );
            };

            // Update global fee tracking for LP positions
            update_fees_global(
                0, 
                0,
                amount_fee_out_rest,
                amount_fee_debt_out_rest,
                k_sqrt_diff,
                metadata
            ); 
            // Update pool reserves after swap
            update(
                reserve.reserve_x + amount_in,
                reserve.reserve_y - amount_out_raw,
                reserve.reserve_debt_x,
                reserve.reserve_debt_y - amount_debt_out_raw,
                reserve
            );
        } else {
            // ====== SWAPPING Y FOR X ====== 
            // Verify sender has enough Y tokens
            assert!(
                fa_utils::balance_of(signer::address_of(sender), address_fa_y) >= amount_in,
                ERR_INSUFFICIENT_INPUT_BALANCE
            );

            // Transfer input tokens from sender to pool
            let fa_y_in = fa_utils::withdraw_fa_from_address(
                sender,
                address_fa_y,
                amount_in
            );
            fungible_asset::deposit(metadata.store_y, fa_y_in);

            let amount_fee_out_rest = amount_fee_out;
            let amount_fee_debt_out_rest = amount_debt_fee_out;
            if (amount_out > 0) {
                // Transfer output tokens (X) from pool to recipient
                let fa_x_out = fungible_asset::withdraw(
                    &resource_signer, 
                    metadata.store_x,
                    amount_out
                );
                fa_utils::deposit(
                    recipient_addr,
                    fa_x_out
                );
                // Process fees for X tokens - split between LP fees and protocol fees
                let fa_x_fee_out = fungible_asset::withdraw(
                    &resource_signer,
                    metadata.store_x,
                    amount_fee_out
                );
                let (amount_protocol_fee_out, _) = pool_math_utils::get_extracted_fees(
                    amount_fee_out
                );
                // Safety check: prevent underflow
                assert!(amount_protocol_fee_out <= amount_fee_out, ERR_INVALID_AMOUNT);
                amount_fee_out_rest = amount_fee_out - amount_protocol_fee_out; // Fixed: prevent underflow
                let fa_x_protocol_fee_out = fungible_asset::extract(
                    &mut fa_x_fee_out,
                    amount_protocol_fee_out
                );
                // Deposit LP fees to fee store
                fungible_asset::deposit(
                    metadata.store_fee_x,
                    fa_x_fee_out
                );
                // Deposit protocol fees to protocol fee store
                fungible_asset::deposit(
                    metadata.store_protocol_fee_x,
                    fa_x_protocol_fee_out
                );
            };
            
            if (amount_debt_out > 0) {
                // Transfer debt tokens (ciX) from pool to recipient
                let fa_debt_x_out = fungible_asset::withdraw(
                    &resource_signer, 
                    metadata.store_debt_x,
                    amount_debt_out
                );
                fa_utils::deposit(
                    recipient_addr,
                    fa_debt_x_out
                );
                // Process fees for debt X tokens - split between LP fees and protocol fees
                let fa_debt_x_fee_out = fungible_asset::withdraw(
                    &resource_signer,
                    metadata.store_debt_x,
                    amount_debt_fee_out
                );
                let (amount_protocol_debt_fee_out, _) = pool_math_utils::get_extracted_fees(
                    amount_debt_fee_out
                );
                amount_fee_debt_out_rest -= amount_protocol_debt_fee_out;
                
                let fa_debt_x_protocol_fee_out = fungible_asset::extract(
                    &mut fa_debt_x_fee_out,
                    amount_protocol_debt_fee_out
                );
                // Deposit LP debt fees to debt fee store
                fungible_asset::deposit(
                    metadata.store_fee_debt_x,
                    fa_debt_x_fee_out
                );
                // Deposit protocol debt fees to protocol debt fee store
                fungible_asset::deposit(
                    metadata.store_protocol_fee_debt_x, // Fixed: was using store_protocol_fee_x instead of debt_y
                    fa_debt_x_protocol_fee_out
                );
            };

            // Update global fee tracking for LP positions
            update_fees_global(
                amount_fee_out_rest,
                amount_fee_debt_out_rest,
                0, 
                0,
                k_sqrt_diff,
                metadata
            );
            // Update pool reserves after swap
            update(
                reserve.reserve_x - amount_out_raw,
                reserve.reserve_y + amount_in,
                reserve.reserve_debt_x - amount_debt_out_raw,
                reserve.reserve_debt_y,
                reserve
            );
        };

        // Emit event
        emit_swap_event(
            signer::address_of(sender),
            pool_id,
            amount_in,
            x_for_y,
            amount_out,
            amount_debt_out,
            recipient_addr
        );
    
        (amount_out, amount_debt_out)
    }

    /// Emits a swap event for the given parameters
    public fun emit_swap_event(
        sender_addr: address,
        pool_id: u64,
        amount_in: u64,
        x_for_y: bool,
        amount_out: u64,
        amount_debt_out: u64,
        recipient_addr: address
    ) acquires PairEventHolder {
        let pair_event_holder = borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT);
        event::emit_event<SwapEvent>(
            &mut pair_event_holder.swap,
            SwapEvent {
                sender_addr,
                pool_id,
                amount_in,
                x_for_y,
                amount_out,
                amount_debt_out,
                recipient_addr
            }
        );
    }

    /// Asserts that a pair is created for either (X, Y) or (Y, X)
    public fun is_pool_created(pool_id: u64) acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(
            swap_info.next_pool_id > pool_id,
            ERR_POOL_NOT_CREATED
        );
    }

    /// Asserts that a pair is not created for both (X, Y) and (Y, X)
    public fun is_pool_not_created(pool_id: u64) acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(
            swap_info.next_pool_id <= pool_id,
            ERR_POOL_CREATED
        );
    }

    /// Collects accumulated fees from a liquidity position
    public fun collect_fees(
        sender: &signer,
        pool_id: u64,
        nft_addr: address,
        recipient_addr: address
    ) : (
        u64, // collected_fee_x
        u64, // collected_fee_y
        u64, // collected_fee_debt_x 
        u64  // collected_fee_debt_y
    ) acquires TokenPairMetadatas, PairEventHolder {
        let sender_addr = signer::address_of(sender);
        let resource_signer = package_manager::get_resource_signer();
        
        // 1. Access position metadata
        let (
            k_sqrt_added, // k_sqrt_added
            fee_growth_inside_x_x128, // fee_growth_inside_x_x128
            fee_growth_inside_y_x128, // fee_growth_inside_y_x128
            fee_growth_inside_debt_x_x128, // fee_growth_inside_debt_x_x128
            fee_growth_inside_debt_y_x128, // fee_growth_inside_debt_y_x128
            fee_owed_x, // fee_owed_x
            fee_owed_y, // fee_owed_y
            fee_owed_debt_x, // fee_owed_debt_x
            fee_owed_debt_y // fee_owed_debt_y
        ) = position::get_position_info(
            signer::address_of(sender),
            pool_id, 
            nft_addr
        );
        // 2. Get current global fee growth
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut(pool_id, metadatas);
        
        // 3. Calculate fee delta
        let fee_delta_x = metadata.global_x_fee_growth_x128 - fee_growth_inside_x_x128;
        let fee_delta_y = metadata.global_y_fee_growth_x128 - fee_growth_inside_y_x128;
        let fee_delta_debt_x = metadata.global_debt_x_fee_growth_x128 - fee_growth_inside_debt_x_x128;
        let fee_delta_debt_y = metadata.global_debt_y_fee_growth_x128 - fee_growth_inside_debt_y_x128;

        // 4. Calculate actual fee amounts based on liquidity share
        let liquidity_share = k_sqrt_added;
        let total_k_sqrt = metadata.k_sqrt_last - metadata.k_sqrt_locked;
        
        let collected_fee_x = pool_math_utils::get_collected_fee_amount(fee_delta_x, liquidity_share, total_k_sqrt);
        let collected_fee_y = pool_math_utils::get_collected_fee_amount(fee_delta_y, liquidity_share, total_k_sqrt);
        let collected_fee_debt_x = pool_math_utils::get_collected_fee_amount(fee_delta_debt_x, liquidity_share, total_k_sqrt);
        let collected_fee_debt_y = pool_math_utils::get_collected_fee_amount(fee_delta_debt_y, liquidity_share, total_k_sqrt);

        // 5. Update position state
        position::update_position_fee_growth_inside(
            signer::address_of(sender),
            pool_id,
            nft_addr,
            metadata.global_x_fee_growth_x128,
            metadata.global_y_fee_growth_x128,
            metadata.global_debt_x_fee_growth_x128,
            metadata.global_debt_y_fee_growth_x128
        );
        // Reset the fee growth inside to zero
        position::reset_position_fee_owed(
            signer::address_of(sender),
            pool_id,
            nft_addr
        );

        // 6. Transfer fees to sender
        let address_fa_x = fa_utils::get_address_from_store(metadata.store_fee_x);
        let address_fa_y = fa_utils::get_address_from_store(metadata.store_fee_y);
        let address_fa_debt_x = fa_utils::get_address_from_store(metadata.store_fee_debt_x);
        let address_fa_debt_y = fa_utils::get_address_from_store(metadata.store_fee_debt_y);

        // Withdraw fees from fee stores
        let fa_x = fungible_asset::withdraw(&resource_signer, metadata.store_fee_x, collected_fee_x);
        let fa_y = fungible_asset::withdraw(&resource_signer, metadata.store_fee_y, collected_fee_y);
        let fa_debt_x = fungible_asset::withdraw(&resource_signer, metadata.store_fee_debt_x, collected_fee_debt_x);
        let fa_debt_y = fungible_asset::withdraw(&resource_signer, metadata.store_fee_debt_y, collected_fee_debt_y);

        // Deposit to sender
        fa_utils::deposit(recipient_addr, fa_x);
        fa_utils::deposit(recipient_addr, fa_y);
        fa_utils::deposit(recipient_addr, fa_debt_x);
        fa_utils::deposit(recipient_addr, fa_debt_y);

        // 7. Emit event if needed (có thể thêm event sau)
        event::emit_event<CollectFeesEvent>(
            &mut borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT).collect_fees,
            CollectFeesEvent {
                sender_addr,
                pool_id,
                nft_addr,     
                amount_x: collected_fee_x,
                amount_y: collected_fee_y,
                amount_debt_x: collected_fee_debt_x,
                amount_debt_y: collected_fee_debt_y
            }
        );
        (
            collected_fee_x,
            collected_fee_y,
            collected_fee_debt_x,
            collected_fee_debt_y
        )
    }

    public fun get_fees(pool_id: u64): (
        u64, // fee_x
        u64, // fee_y
        u64, // debt_fee_x
        u64,  // debt_fee_y
        u64, // protocol_fee_x
        u64,  // protocol_fee_y
        u64, // protocol_fee_debt_x
        u64  // protocol_fee_debt_y
    ) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        (
            fungible_asset::balance(metadata.store_fee_x),
            fungible_asset::balance(metadata.store_fee_y),
            fungible_asset::balance(metadata.store_fee_debt_x),    
            fungible_asset::balance(metadata.store_fee_debt_y),
            fungible_asset::balance(metadata.store_protocol_fee_x),
            fungible_asset::balance(metadata.store_protocol_fee_y),
            fungible_asset::balance(metadata.store_protocol_fee_debt_x),
            fungible_asset::balance(metadata.store_protocol_fee_debt_y)
        )
    }

    public fun get_address_x(pool_id: u64): address acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        fa_utils::get_address_from_store(metadata.store_x)
    }

    public fun get_address_y(pool_id: u64): address acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        fa_utils::get_address_from_store(metadata.store_y)
    }

    public fun get_address_debt_x(pool_id: u64): address acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        fa_utils::get_address_from_store(metadata.store_debt_x)
    }

    public fun get_address_debt_y(pool_id: u64): address acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        fa_utils::get_address_from_store(metadata.store_debt_y)
    }

    // Asserts that the sender is the admin of the swap module
    public fun assert_admin(sender: &signer, swap_info: &SwapInfo) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == swap_info.admin, ERR_NOT_ADMIN)
    }

    public fun get_tokens(pool_id: u64): (
        address, // address_x
        address, // address_y
        address, // address_debt_x
        address  // address_debt_y
    ) acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        (
            fa_utils::get_address_from_store(metadata.store_x),
            fa_utils::get_address_from_store(metadata.store_y),
            fa_utils::get_address_from_store(metadata.store_debt_x),
            fa_utils::get_address_from_store(metadata.store_debt_y)
        )
    }

    // Collects protocol fees from a pool and deposits them to the fee recipient
    public entry fun collect_protocol(
        sender: &signer,
        pool_id: u64,
    ) acquires TokenPairMetadatas, SwapInfo, PairEventHolder {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert_admin(sender, swap_info);
        let resource_signer = package_manager::get_resource_signer();
        // Get metadata for the pool
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata_mut(pool_id, metadatas);

        // Collect protocol fees from the pool
        let fa_x = fungible_asset::withdraw(&resource_signer, metadata.store_protocol_fee_x, fungible_asset::balance(metadata.store_protocol_fee_x));
        let fa_y = fungible_asset::withdraw(&resource_signer, metadata.store_protocol_fee_y, fungible_asset::balance(metadata.store_protocol_fee_y));
        let fa_debt_x = fungible_asset::withdraw(&resource_signer, metadata.store_protocol_fee_debt_x, fungible_asset::balance(metadata.store_protocol_fee_debt_x));
        let fa_debt_y = fungible_asset::withdraw(&resource_signer, metadata.store_protocol_fee_debt_y, fungible_asset::balance(metadata.store_protocol_fee_debt_y));

        // Deposit collected fees to sender's account
        fa_utils::deposit(swap_info.fee_to, fa_x);
        fa_utils::deposit(swap_info.fee_to, fa_y);
        fa_utils::deposit(swap_info.fee_to, fa_debt_x);
        fa_utils::deposit(swap_info.fee_to, fa_debt_y);

        // Emit event for protocol fee collection
        event::emit_event<CollectProtocolEvent>(
            &mut borrow_global_mut<PairEventHolder>(RESOURCE_ACCOUNT).collect_protocol,
            CollectProtocolEvent {
                sender_addr: signer::address_of(sender),
                pool_id,
                amount_x: fungible_asset::balance(metadata.store_protocol_fee_x),
                amount_y: fungible_asset::balance(metadata.store_protocol_fee_y),
                amount_debt_x: fungible_asset::balance(metadata.store_protocol_fee_debt_x),
                amount_debt_y: fungible_asset::balance(metadata.store_protocol_fee_debt_y)
            }
        );
    }

    /// Get product of reserves for a given pool
    /// Use to check if the reserve is altered
    public fun get_product_reserves_sqrt(
        pool_id: u64
    ): u64 acquires TokenPairReserves {
        let reserves = borrow_global_mut<TokenPairReserves>(RESOURCE_ACCOUNT);
        let reserve = get_reserve(pool_id, reserves);
        pool_math_utils::get_k_sqrt(
            reserve.reserve_x, 
            reserve.reserve_y, 
            reserve.reserve_debt_x,
            reserve.reserve_debt_y
        )
    }

    /// Get the reserve with balance
    /// Use to ensure the balance is synced with reserves
    public fun get_product_balances_sqrt(
        pool_id: u64
    ): u64 acquires TokenPairMetadatas {
        let metadatas = borrow_global_mut<TokenPairMetadatas>(RESOURCE_ACCOUNT);
        let metadata = get_metadata(pool_id, metadatas);
        pool_math_utils::get_k_sqrt(
            fungible_asset::balance(metadata.store_x),
            fungible_asset::balance(metadata.store_y),
            fungible_asset::balance(metadata.store_debt_x),
            fungible_asset::balance(metadata.store_debt_y)
        )
    }

    /// Test-only function to initialize the module (for unit tests)
    #[test_only]
    public fun init_for_test() {
        let resource_signer = package_manager::get_resource_signer();
        init_module(&resource_signer);
    }
}