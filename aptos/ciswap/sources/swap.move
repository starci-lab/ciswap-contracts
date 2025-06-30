/// CiSwap with (X + ciX) (Y + ciY) = K
module ciswap::swap {
//     // Importing necessary modules from the standard library, Aptos framework, and local modules
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
    use aptos_framework::fungible_asset::{ Self, FungibleStore };
    use ciswap::pool_math_utils::{Self};
    use ciswap::package_manager::{Self};
    use aptos_framework::fungible_asset::{Metadata};
    use ciswap::position::{Self};
    use ciswap::fa_utils::{Self};
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

//     // ------------------------------------------------------------------------
//     // Structs
//     // ------------------------------------------------------------------------


        struct FABalance has key, store {
            balance: u64, // The balance of the token
            fa_address: address, // The address of the fungible asset
        }

//     /// The LP Token type, representing liquidity provider tokens for a pair.
//     ///
//     /// # Type Parameters
//     /// - `X`: The first token type in the pair (phantom, not stored directly)
//     /// - `Y`: The second token type in the pair (phantom, not stored directly)
//     struct LiqudityPositon<phantom X, phantom Y> has key {}

//     /// Virtual token for the token X in a pair (used for virtual liquidity).
//     ///
//     /// # Type Parameters
//     /// - `X`: The token this virtual token represents (phantom)
//     /// - `Y`: The other token in the pair (phantom)
//     struct VirtualX<phantom X, phantom Y> has key {}

    /// The event emitted when liquidity is added to a pool.
    ///
    /// # Fields
    /// - `sender_addr`: Address of the liquidity provider
    /// - `pool_index`: Address of the pool
    /// - `amount_x`: Amount of token X added
    /// - `amount_y`: Amount of token Y added
    /// - `liquidity`: Amount of LP tokens minted
    /// - `fee_amount`: Fee amount collected
    struct AddLiquidityEvent has drop, store {
        sender_addr: address, // Address of the liquidity provider
        pool_id: u64,   // Address of the pool
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
        pool_index: u64,              // Address of the pool
        amount_debt_x: u64,        // Amount of virtual X redeemed
        amount_debt_y: u64,        // Amount of virtual Y redeemed
        redeemed_amount_x: u64,       // Amount of real X received
        redeemed_amount_y: u64,       // Amount of real Y received
        recipient_addr: address       // Address receiving the real tokens
    }

    struct CollectFeeEvent has drop, store {
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
        remove_liquidity: EventHandle<RemoveLiquidityEvent>,
        swap: EventHandle<SwapEvent>,
        redeem: EventHandle<RedeemEvent>,
        collect_fee: EventHandle<CollectFeeEvent>
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
        balance_x: FABalance, // Pool's current balance of token X
        balance_y: FABalance, // Pool's current balance of token Y
        fee_balance_x: FABalance, // Accumulated fees in token X
        fee_balance_y: FABalance, // Accumulated fees in token Y
        global_k_sqrt_fee_growth: u64, // Global fee growth for the pair (used for fee distribution)
        balance_debt_x: FABalance, // Pool's current balance of virtual X
        balance_debt_y: FABalance, // Pool's current balance of virtual Y
    }

    /// Table of all TokenPairMetadata for a given pair type.
    ///
    /// # Fields
    /// - `metadatas`: Table mapping pool address to TokenPairMetadata
    struct TokenPairMetadatas has key, store {
        metadatas: Table<u64, TokenPairMetadata>, // Mapping pool address to metadata
    }

//     /// Reserve information for a token pair (real and virtual reserves).
//     ///
//     /// # Fields
//     /// - `reserve_x`: Real reserve of token X
//     /// - `reserve_y`: Real reserve of token Y
//     /// - `reserve_debt_x`: Virtual reserve of X
//     /// - `reserve_debt_y`: Virtual reserve of Y
//     /// - `block_timestamp_last`: Last update timestamp
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
    const ERROR_POOL_NOT_CREATED: u64 = 12; // Pair not created
    const ERROR_POOL_CREATED: u64 = 13; // Pair already created

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
        amount_debt_y: u64     // Initial virtual Y balance
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
        // Store SwapInfo in the resource account
        let resource_signer = package_manager::get_resource_signer();
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
                collect_fee: account::new_event_handle<CollectFeeEvent>(&resource_signer)
            }
        );
    }

//     fun create_collection<X,Y>(creator: &signer) {
//         let royalty = option::none();
//         // Maximum supply cannot be changed after collection creation
//         collection::create_unlimited_collection(
//             creator,
//             string::utf8(b"My Collection Description"),
//             max_supply,
//             string::utf8(b"My Collection"),
//             royalty,
//             string::utf8(b"https://mycollection.com"),
//         );
// }

//     /// Registers the LP token type for a pair in the coin module.
//     ///
//     /// # Type Parameters
//     /// - `X`, `Y`: Token types for the LP token
//     /// # Arguments
//     /// - `sender`: The signer to register the coin store
//     public fun register_lp<X, Y>(sender: &signer) {
//         coin::register<LPToken<X, Y>>(sender);
//     }

//     /// Registers the virtual token type for a pair in the coin module.
//     ///
//     /// # Type Parameters
//     /// - `X`, `Y`: Token types for the virtual token
//     /// # Arguments
//     /// - `sender`: The signer to register the coin store
//     public fun register_debt_x<X,Y>(sender: &signer) {
//         coin::register<VirtualX<X,Y>>(sender);
//     }

    /// Checks if a pair is already created for the given pool address.
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Token types for the pair
    /// # Arguments
    /// - `pool_index`: Address of the pool
    /// # Returns
    /// - `bool`: True if the pair exists, false otherwise

//     /// Creates a new token pair pool with specified virtual balances.
//     ///
//     /// # Type Parameters
//     /// - `X`, `Y`: Token types for the pair
//     /// # Arguments
//     /// - `sender`: The signer creating the pair
//     /// - `pool_index`: Pool address (provided off-chain)
//     /// - `amount_debt_x`: Initial virtual X liquidity
//     /// - `amount_debt_y`: Initial virtual Y liquidity
//     ///
//     /// # Effects
//     /// - Checks that the pair is not already created
//     /// - Transfers creation fee
//     /// - Initializes LP and virtual tokens
//     /// - Stores metadata and reserves
//     /// - Emits PairCreatedEvent
    public fun create_pair(
        sender: &signer,
        address_x: address, // Address of token X
        address_y: address, // Address of token Y
        amount_debt_x: u64, // Initial virtual X liquidity
        amount_debt_y: u64  // Initial virtual Y liquidity
    ) acquires SwapInfo
    //, TokenPairMetadatas, TokenPairReserves
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
        position::create_collection(
            &resource_signer,
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

        let salt_x = string::utf8(b"ci-");
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
        let balance_debt_x = fungible_asset::mint(
            &fa_utils::get_mint_ref(address_x),
            amount_debt_x,
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

        let salt_y = string::utf8(b"ci-");
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
        let balance_debt_y = fungible_asset::mint(
            &fa_utils::get_mint_ref(address_y),
            amount_debt_y,
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
                k_sqrt_last: locked_liquidity,
                fee_balance_x: FABalance {
                    balance: 0,
                    fa_address: address_x
                },
                fee_balance_y: FABalance {
                    balance: 0,
                    fa_address: address_y
                },
                balance_x: FABalance {
                    balance: 0,
                    fa_address: address_x
                },
                balance_y: FABalance {
                    balance: 0,
                    fa_address: address_y
                },
                balance_debt_x: FABalance {
                    balance: amount_debt_x,
                    fa_address: address_debt_x
                },
                balance_debt_y: FABalance {
                    balance: amount_debt_y,
                    fa_address: address_debt_y
                },
                global_k_sqrt_fee_growth: 0, 
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
                amount_debt_y
            }
        );
    }

//     /// Returns the current balances of X, Y, virtual X, and virtual Y in the pool
//     public fun token_balances<X, Y>(pool_index: u64): (u64, u64, u64, u64) acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata<X, Y>(pool_index, metadatas);
//         (
//             coin::value(&metadata.balance_x),
//             coin::value(&metadata.balance_y),
//             coin::value(&metadata.balance_debt_x),
//             coin::value(&metadata.balance_debt_y)
//         )
//     }

//     // retrieve the metadata by X,Y and pool address
//     /// Returns a reference to the metadata for a given pool address
//     public fun get_metadata<X, Y>(
//         pool_index: u64, 
//         metadatas: &mut TokenPairMetadatas<X, Y>
//     ): &TokenPairMetadata<X, Y> {
//         table::borrow(&mut metadatas.metadatas, pool_index)  
//     }

//     /// Returns a mutable reference to the metadata for a given pool address
//     public fun get_metadata_mut<X, Y>(
//         pool_index: u64, 
//         metadatas: &mut TokenPairMetadatas<X, Y>
//     ): &mut TokenPairMetadata<X, Y> {
//         table::borrow_mut(&mut metadatas.metadatas, pool_index)  
//     }

//     // retrieve the reserve by X,Y and pool address
//     /// Returns a reference to the reserves for a given pool address
//     public fun get_reserve<X, Y>(
//         pool_index: u64,
//         reserves: &mut TokenPairReserves<X, Y>
//     ): &TokenPairReserve<X, Y> {
//         table::borrow(&mut reserves.reserves, pool_index)  
//     }

//     /// Returns a mutable reference to the reserves for a given pool address
//     public fun get_reserve_mut<X, Y>(
//         pool_index: u64,
//         reserves: &mut TokenPairReserves<X, Y>
//     ): &mut TokenPairReserve<X, Y> {
//         table::borrow_mut(&mut reserves.reserves, pool_index)  
//     }

//     /// Returns the amount of locked LP tokens in the pool
//     public fun balance_locked_lp<X, Y>(pool_index: u64): u64 acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let meta = get_metadata<X, Y>(pool_index, metadatas);
//         coin::value(&meta.balance_locked_lp)
//     }

//     /// Extracts a specified amount of X from the pool's balance (internal use)
//     fun extract_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<X> {
//         assert!(coin::value<X>(&metadata.balance_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
//         coin::extract(&mut metadata.balance_x, amount)
//     }

//     /// Extracts a specified amount of Y from the pool's balance (internal use)
//     fun extract_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<Y> {
//         assert!(coin::value<Y>(&metadata.balance_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
//         coin::extract(&mut metadata.balance_y, amount)
//     }

//     /// Extracts a specified amount of virtual X from the pool's balance (internal use)
//     fun extract_debt_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<X, Y>> {
//         assert!(coin::value<VirtualX<X, Y>>(&metadata.balance_debt_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
//         coin::extract(&mut metadata.balance_debt_x, amount)
//     }   
//     /// Extracts a specified amount of virtual Y from the pool's balance (internal use)
//     fun extract_debt_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): coin::Coin<VirtualX<Y, X>> {
//         assert!(coin::value<VirtualX<Y, X>>(&metadata.balance_debt_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
//         coin::extract(&mut metadata.balance_debt_y, amount)
//     }

//     /// Redeems virtual tokens for real tokens, transferring them to the recipient
//     public fun redeem<X, Y>(
//         sender: &signer,
//         pool_index: u64,
//         amount_debt_x: u64,
//         amount_debt_y: u64,
//         recipient_addr: address
//     ): (
//         u64, 
//         u64
//     ) acquires TokenPairMetadatas, TokenPairReserves, PairEventHolder {
//         // Get references to metadata and reserves
//         let sender_addr = signer::address_of(sender);
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata_mut<X, Y>(pool_index, metadatas);
//         let reserve = get_reserve_mut<X, Y>(pool_index, reserves);
//         // Withdraw virtual tokens from sender
//         let coin_debt_x = coin::withdraw<VirtualX<X, Y>>(sender, amount_debt_x);
//         let coin_debt_y = coin::withdraw<VirtualX<Y, X>>(sender, amount_debt_y);
//         // Calculate the real tokens to be redeemed
//         let redeemed_amount_x = pool_math_utils::get_redeemed_amount(amount_debt_x);
//         let redeemed_amount_y = pool_math_utils::get_redeemed_amount(amount_debt_y);
//         // Ensure the pool has enough real tokens to redeem
//         assert!(coin::value(&metadata.balance_debt_x) >= redeemed_amount_x, ERROR_REDEMPTION_NOT_ENOUGH);
//         assert!(coin::value(&metadata.balance_debt_y) >= redeemed_amount_y, ERROR_REDEMPTION_NOT_ENOUGH);
//         // Burn the virtual tokens
//         coin::burn<VirtualX<X, Y>>(coin_debt_x, &mut metadata.burn_debt_x_cap);
//         coin::burn<VirtualX<Y, X>>(coin_debt_y, &mut metadata.burn_debt_y_cap);
//         // Mint new virtual tokens to the pool to maintain liquidity
//         let redeemed_x = coin::mint<VirtualX<X, Y>>(redeemed_amount_x, &mut metadata.mint_debt_x_cap);
//         let redeemed_y = coin::mint<VirtualX<Y, X>>(redeemed_amount_y, &mut metadata.mint_debt_y_cap);
//         // Add the new virtual tokens to the pool's balance
//         coin::merge(&mut metadata.balance_debt_x, redeemed_x);
//         coin::merge(&mut metadata.balance_debt_y, redeemed_y);
//         // Extract real tokens from the pool and deposit to recipient
//         let coin_x = extract_x<X, Y>(redeemed_amount_x, metadata);
//         let coin_y = extract_y<X, Y>(redeemed_amount_y, metadata);
//         coin::deposit(recipient_addr, coin_x);
//         coin::deposit(recipient_addr, coin_y);
//         // Update the reserves to reflect the redemption
//         update<X, Y>(
//             reserve.reserve_x - redeemed_amount_x,
//             reserve.reserve_y - redeemed_amount_y,
//             reserve.reserve_debt_x + redeemed_amount_x,
//             reserve.reserve_debt_y + redeemed_amount_y,
//             reserve
//         );

//         // Emit the redeem event
//         event::emit_event<RedeemEvent<X, Y>>(
//             &mut borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT).redeem,
//             RedeemEvent {
//                 sender_addr,
//                 pool_index,
//                 amount_debt_x,
//                 amount_debt_y,
//                 redeemed_amount_x,
//                 redeemed_amount_y,
//                 recipient_addr
//             }
//         );
//         (
//             redeemed_amount_x, 
//             redeemed_amount_y
//         )
//     }

//     /// Returns the current reserves (real and virtual) for a pool
//     public fun token_reserves<X, Y>(
//         pool_index: u64
//     ): (
//         u64, 
//         u64, 
//         u64,
//         u64
//     ) acquires TokenPairReserves {
//         let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
//         let reserve = get_reserve<X, Y>(pool_index, reserves);
//         (
//             reserve.reserve_x, 
//             reserve.reserve_y, 
//             reserve.reserve_debt_x, 
//             reserve.reserve_debt_y
//         )
//     }   

//     /// Deposits X into the pool's balance (internal use)
//     fun deposit_x<X, Y>(pool_index: u64, amount: coin::Coin<X>) acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata_mut<X, Y>(pool_index , metadatas);
//         coin::merge(&mut metadata.balance_x, amount);
//     }

//     /// Deposits Y into the pool's balance (internal use)
//     fun deposit_y<X, Y>(pool_index: u64, amount: coin::Coin<Y>) acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata_mut<X, Y>(pool_index, metadatas);
//         coin::merge(&mut metadata.balance_y, amount);
//     }

//     /// Mints LP tokens to a specified address
//     fun mint_lp_to<X, Y>(
//         to: address,
//         amount: u64,
//         mint_cap: &coin::MintCapability<LPToken<X, Y>>
//     ) {
//         let coins = coin::mint<LPToken<X, Y>>(amount, mint_cap);
//         coin::deposit(to, coins);
//     }

//     /// Mints LP tokens and returns them (internal use)
//     fun mint_lp<X, Y>(amount: u64, mint_cap: &coin::MintCapability<LPToken<X, Y>>): coin::Coin<LPToken<X, Y>> {
//         coin::mint<LPToken<X, Y>>(amount, mint_cap)
//     }

//     /// Returns the total supply of LP tokens for a pair
//     public fun total_lp_supply<X, Y>(): u128 {
//         option::get_with_default(
//             &coin::supply<LPToken<X, Y>>(),
//             0u128
//         )
//     }

//     /// Returns the last recorded sqrt(K) for a pool (used for fee calculation)
//     public fun k_sqrt<X, Y>(pool_index: u64) : u64 acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata<X, Y>(pool_index, metadatas);
//         metadata.k_sqrt_last
//     }

//     /// Returns the accumulated fee amount in LP tokens for a pool
//     public fun fee_amount<X, Y>(pool_index: u64): u64 acquires TokenPairMetadatas {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata<X, Y>(pool_index, metadatas);
//         coin::value(&metadata.fee_amount)
//     }

//     /// Mints new LP tokens for liquidity providers based on the change in sqrt(K)
//     fun mint<X, Y>(pool_index: u64): (coin::Coin<LPToken<X, Y>>, u64) acquires TokenPairMetadatas, TokenPairReserves {
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata_mut<X, Y>(pool_index, metadatas);
//         let (
//             balance_x, 
//             balance_y, 
//             balance_debt_x,
//             balance_debt_y
//         ) = (
//             coin::value(&metadata.balance_x), 
//             coin::value(&metadata.balance_y),
//             coin::value(&metadata.balance_debt_x),
//             coin::value(&metadata.balance_debt_y)
//         );

//         let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
//         let reserve = get_reserve_mut<X, Y>(pool_index, reserves);
//         // Calculate the root K for the last mint and current balances
//         let root_k_sqrt = pool_math_utils::get_k_sqrt(
//             reserve.reserve_x, 
//             reserve.reserve_y, 
//             reserve.reserve_debt_x,
//             reserve.reserve_debt_y
//         );
//         let k_sqrt = pool_math_utils::get_k_sqrt(
//             balance_x, 
//             balance_y, 
//             balance_debt_x,
//             balance_debt_y
//         ); 
//         // Calculate the difference in K
//         let k_sqrt_diff = k_sqrt - root_k_sqrt; 

//         // Calculate the LP and fee amounts to mint
//         let (to_lp, fee) = pool_math_utils::get_liquidity_and_fee_amount(
//             k_sqrt_diff,
//         );
//         // Mint LP tokens and fee tokens
//         let lp = mint_lp<X, Y>((to_lp as u64), &metadata.mint_cap);
//         let fee_coin = mint_lp<X, Y>(fee, &metadata.mint_cap);
//         coin::merge(&mut metadata.fee_amount, fee_coin);
//         metadata.k_sqrt_last = k_sqrt;
//         (lp, fee)
//     }

//     /// Adds liquidity to the pool directly, returning optimal amounts and LP tokens
//     fun add_liquidity_direct<X, Y>(
//         pool_index: u64,
//         x: coin::Coin<X>,
//         y: coin::Coin<Y>,
//     ): (
//         u64, 
//         u64, 
//         coin::Coin<LPToken<X, Y>>, u64, 
//         coin::Coin<X>, 
//         coin::Coin<Y>
//     ) acquires TokenPairReserves, TokenPairMetadatas {
//         let amount_x = coin::value(&x);
//         let amount_y = coin::value(&y);
//         let (
//             reserve_x, 
//             reserve_y, 
//             reserve_debt_x, 
//             reserve_debt_y
//         ) = token_reserves<X, Y>(pool_index);
//         // Calculate optimal amounts to add based on current reserves
//         let (a_x, a_y) = {
//             let amount_y_optimal = pool_math_utils::quote(
//                 amount_x, 
//                 reserve_x, 
//                 reserve_y, 
//                 reserve_debt_x,
//                 reserve_debt_y
//                 );
//             if (amount_y_optimal <= amount_y) {
//                 (amount_x, amount_y_optimal)
//             } else {
//                 let amount_x_optimal = pool_math_utils::quote(
//                     amount_y, 
//                     reserve_y,
//                     reserve_x,
//                     reserve_debt_y,
//                     reserve_debt_x
//                 );
//                 assert!(amount_x_optimal <= amount_x, ERROR_INVALID_AMOUNT);
//                 (amount_x_optimal, amount_y)
//             }
//         };

//         assert!(a_x <= amount_x, ERROR_INSUFFICIENT_AMOUNT);
//         assert!(a_y <= amount_y, ERROR_INSUFFICIENT_AMOUNT);

//         // Extract any excess tokens and deposit the optimal amounts
//         let left_x = coin::extract(&mut x, amount_x - a_x);
//         let left_y = coin::extract(&mut y, amount_y - a_y);
//         deposit_x<X, Y>(pool_index, x);
//         deposit_y<X, Y>(pool_index, y);
//         let (lp, fee_amount) = mint<X, Y>(pool_index);
//         (a_x, a_y, lp, fee_amount, left_x, left_y)
//     }

//     /// Checks if the sender has a CoinStore for type X, and registers if not
//     public fun check_or_register_coin_store<X>(sender: &signer) {
//         if (!coin::is_account_registered<X>(signer::address_of(sender))) {
//             coin::register<X>(sender);
//         };
//     }

//     /// Adds liquidity to the pool, mints LP tokens, and emits an event
//     public fun add_liquidity<X, Y>(
//         sender: &signer,
//         pool_index: u64,
//         amount_x: u64,
//         amount_y: u64
//     ): (u64, u64, u64) acquires TokenPairReserves, TokenPairMetadatas, PairEventHolder {
//         // Withdraw tokens from sender and add liquidity
//         let (a_x, a_y, coin_lp, fee_amount, coin_left_x, coin_left_y) = add_liquidity_direct(
//             pool_index, 
//             coin::withdraw<X>(sender, amount_x), 
//             coin::withdraw<Y>(sender, amount_y)
//         );
//         let sender_addr = signer::address_of(sender);
//         let lp_amount = coin::value(&coin_lp);
//         assert!(lp_amount > 0, ERROR_INSUFFICIENT_LIQUIDITY);
//         check_or_register_coin_store<LPToken<X, Y>>(sender);
//         coin::deposit(sender_addr, coin_lp);
//         coin::deposit(sender_addr, coin_left_x);
//         coin::deposit(sender_addr, coin_left_y);

//         // Emit the add liquidity event
//         let pair_event_holder = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
//         event::emit_event<AddLiquidityEvent<X, Y>>(
//             &mut pair_event_holder.add_liquidity,
//             AddLiquidityEvent<X, Y> {
//                 sender_addr,
//                 pool_index,
//                 amount_x: a_x,
//                 amount_y: a_y,
//                 liquidity: lp_amount,
//                 fee_amount: (fee_amount as u64),
//             }
//         );
//         (a_x, a_y, lp_amount)
//     }

//     /// Sets the protocol fee recipient (admin only)
//     public entry fun set_fee_to(sender: &signer, new_fee_to: address) acquires SwapInfo {
//         let sender_addr = signer::address_of(sender);
//         let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
//         assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
//         swap_info.fee_to = new_fee_to;
//     }

//     /// Sets the admin address (admin only)
//     public entry fun set_admin(sender: &signer, new_admin: address) acquires SwapInfo {
//         let sender_addr = signer::address_of(sender);
//         let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
//         assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
//         swap_info.admin = new_admin;
//     }

//     /// Upgrades the swap module by publishing new code (admin only)
//     public entry fun upgrade_swap(
//         sender: &signer, 
//         metadata_serialized: vector<u8>, 
//         code: vector<vector<u8>>
//     ) acquires SwapInfo {
//         let sender_addr = signer::address_of(sender);
//         let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
//         assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
//         let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);
//         code::publish_package_txn(&resource_signer, metadata_serialized, code);
//     }

//     /// Updates the reserves for a pool with new balances and timestamp
//     fun update<X, Y>(
//         balance_x: u64, 
//         balance_y: u64, 
//         balance_debt_x: u64, 
//         balance_debt_y: u64,
//         reserve: &mut TokenPairReserve<X, Y>
//     ) {
//         let block_timestamp = timestamp::now_seconds();
//         reserve.reserve_x = balance_x;
//         reserve.reserve_y = balance_y;
//         reserve.reserve_debt_x = balance_debt_x;
//         reserve.reserve_debt_y = balance_debt_y;
//         reserve.block_timestamp_last = block_timestamp;
//     }

//     /// Swaps tokens in the pool, transferring output to the recipient and emitting an event
//     /// x_for_y: true means swapping X for Y, false means swapping Y for X
//     /// limit_amount_calculated: slippage protection (max output allowed)
//     public fun swap<X, Y>(
//         sender: &signer,
//         pool_index: u64,
//         amount_in: u64,
//         x_for_y: bool,
//         recipient_addr: address,
//         limit_amount_calculated: u64
//     ): (
//         u64, u64
//     ) acquires PairEventHolder, TokenPairMetadatas, TokenPairReserves {
//         assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
//         let reserves = borrow_global_mut<TokenPairReserves<X, Y>>(RESOURCE_ACCOUNT);
//         let reserve =  get_reserve_mut<X, Y>(pool_index, reserves);
//         let metadatas = borrow_global_mut<TokenPairMetadatas<X, Y>>(RESOURCE_ACCOUNT);
//         let metadata = get_metadata_mut<X, Y>(pool_index, metadatas);
//         // Calculate output amounts using pool math
//         let (
//             amount_out, 
//             amount_debt_out
//         ) = pool_math_utils::get_tokens_amount_out(
//             amount_in, 
//             x_for_y, 
//             reserve.reserve_x, 
//             reserve.reserve_y, 
//             reserve.reserve_debt_x, 
//             reserve.reserve_debt_y
//         );

//         // Get the actual reserves (real tokens only)
//         let (actual_x, actual_y) = pool_math_utils::get_actual_x_y(
//             reserve.reserve_x, 
//             reserve.reserve_y, 
//             reserve.reserve_debt_x, 
//             reserve.reserve_debt_y
//         );
//         // Handle swap direction
//         if (x_for_y) {
//             // Swapping X for Y
//             let coin = coin::withdraw<X>(sender, amount_in);
//             coin::merge(&mut metadata.balance_x, coin);
//             assert!(amount_out <= actual_y, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
//             let coins_y_out = coin::zero<Y>();
//             let debt_coins_y_out = coin::zero<VirtualX<Y, X>>();
//             coin::merge(
//                 &mut coins_y_out, 
//                 extract_y(
//                     amount_out, 
//                     metadata
//                 )
//             );
//             coin::merge(
//                 &mut debt_coins_y_out, 
//                 extract_debt_y(
//                     amount_debt_out, 
//                     metadata
//                 )
//             );
//             assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
//             reserve.reserve_y -= amount_out;
//             reserve.reserve_debt_y -= amount_debt_out;
//             reserve.reserve_x += amount_in;
//             coin::deposit(recipient_addr, coins_y_out);
//             coin::deposit(recipient_addr, debt_coins_y_out);
//         } else {
//             // Swapping Y for X
//             let coin = coin::withdraw<Y>(sender, amount_in);
//             coin::merge(&mut metadata.balance_y, coin);
//             assert!(amount_out <= actual_x, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
//             let coins_x_out = coin::zero<X>();
//             let debt_coins_x_out = coin::zero<VirtualX<X, Y>>();
//             coin::merge(
//                 &mut coins_x_out, 
//                 extract_x(
//                     amount_out, 
//                     metadata
//                 )
//             );
//             assert!(amount_out <= limit_amount_calculated, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
//             coin::merge(
//                 &mut debt_coins_x_out, 
//                 extract_debt_x(
//                     amount_debt_out, 
//                     metadata
//                 )
//             );
//             reserve.reserve_x -= amount_out;
//             reserve.reserve_debt_x -= amount_debt_out;
//             reserve.reserve_y += amount_in;
//             coin::deposit(recipient_addr, coins_x_out);
//             coin::deposit(recipient_addr, debt_coins_x_out);
//         };

//         // Emit the swap event
//         emit_swap_event<X, Y>(
//             signer::address_of(sender),
//             pool_index,
//             amount_in,
//             x_for_y,
//             amount_out,
//             amount_debt_out,
//             recipient_addr
//         );
//         (amount_out, amount_debt_out)
//     }

//     /// Emits a swap event for the given parameters
//     public fun emit_swap_event<X, Y>(
//         sender_addr: address,
//         pool_index: u64,
//         amount_in: u64,
//         x_for_y: bool,
//         amount_out: u64,
//         amount_debt_out: u64,
//         recipient_addr: address
//     ) acquires PairEventHolder {
//         let pair_event_holder = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
//         event::emit_event<SwapEvent<X, Y>>(
//             &mut pair_event_holder.swap,
//             SwapEvent<X, Y> {
//                 sender_addr,
//                 pool_index,
//                 amount_in,
//                 x_for_y,
//                 amount_out,
//                 amount_debt_out,
//                 recipient_addr
//             }
//         );
//     }

//     /// Returns the output amounts for a given input and direction, without executing the swap
//     public fun get_amount_out<X, Y>(
//         pool_index: u64,
//         amount_in: u64,
//         x_for_y: bool
//     ): (u64, u64) acquires TokenPairReserves {
//         let (
//             reserve_x, 
//             reserve_y, 
//             reserve_debt_x, 
//             reserve_debt_y
//         ) = token_reserves<X, Y>(pool_index);
//         pool_math_utils::get_tokens_amount_out(
//             amount_in, 
//             x_for_y, 
//             reserve_x, 
//             reserve_y, 
//             reserve_debt_x, 
//             reserve_debt_y
//         )
//     }

//     /// Returns the input amount required to get a desired output, for a given direction
//     public fun get_amount_in<X, Y>(
//         pool_index: u64,
//         amount_out: u64,
//         x_for_y: bool
//     ): ( u64 ) acquires TokenPairReserves {
//         let (
//             reserve_x, 
//             reserve_y, 
//             reserve_debt_x, 
//             reserve_debt_y
//         ) = token_reserves<X, Y>(pool_index);
//         pool_math_utils::get_amount_in(
//             amount_out,
//             x_for_y,
//             reserve_x,
//             reserve_y,
//             reserve_debt_x,
//             reserve_debt_y,
//         )
//     }

    /// Asserts that a pair is created for either (X, Y) or (Y, X)
    public fun is_pool_created(pool_id: u64) acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(
            swap_info.next_pool_id > pool_id,
            ERROR_POOL_NOT_CREATED
        );
    }

    /// Asserts that a pair is not created for both (X, Y) and (Y, X)
    public fun is_pool_not_created(pool_id: u64) acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(
            swap_info.next_pool_id <= pool_id,
            ERROR_POOL_CREATED
        );
    }

//     /// Get swap information, including admin and fee recipient
//     #[view]
//     public fun get_creation_fee_in_apt(): u64 acquires SwapInfo {
//         borrow_global<SwapInfo>(RESOURCE_ACCOUNT).creation_fee_in_apt
//     }

//     /// Get pool creation fee in APT
//     #[view]
//     public fun get_pool_creation_fee_apt(): u64 acquires SwapInfo {
//         coin::value(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).pool_creation_fee_apt)
//     }

//     fun wrap_coin_into_fa<X>(
//         sender: &signer,
//         amount: u64
//     ) {
//         // 1. Withdraw the legacy coin from the user's account
//         let legacy_coin = coin::withdraw<X>(user, amount);
//         // 2. (Optional) burn the legacy coin if needed
//         // This step is not strictly necessary, but can be used to ensure the legacy coin is
//         coin::burn(legacy_coin);
//         // 3. Mint FA tương ứng
//         fungible_asset::mint(copy fa_info, amount);
//     }

//     /// Test-only function to initialize the module (for unit tests)
//     #[test_only]
//     public fun initialize(sender: &signer) {
//         init_module(sender);
//     }
}