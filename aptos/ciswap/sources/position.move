// ===============================================
//  CiSwap Position Module
//  ----------------------------------------------
//  Manages LP NFT positions for liquidity providers
// ===============================================

module ciswap::position {
    //! Converts legacy `coin<T>` tokens into their object-based `fungible_asset` equivalents
    use std::signer::{ Self };
    use aptos_framework::coin::{ Self, Coin };
    use aptos_framework::fungible_asset::{ Self, FungibleAsset, Metadata };
    use aptos_token_objects::collection::{ Self };
    use aptos_token_objects::token::{ Self, Token, BurnRef, MutatorRef };
    use aptos_framework::string::{ Self, String };
    use std::option::{Self, Option};
    use ciswap::u64_utils::{ Self };
    use ciswap::fa_utils::{ Self };
    use aptos_framework::object::{ Self, ConstructorRef };
    use aptos_framework::table::{ Self, Table };
    use ciswap::package_manager::{ Self };

    // -------------------- Structs --------------------
    /// Metadata for an LP NFT collection for a specific pool.
    struct CollectionMetadata has key, store {
        collection_addr: address, // Address of the collection
        name: String, // Name of the collection
        positions: Table<address, Position>, // Mapping from NFT Ad
        next_nft_id: u64 // Next NFT ID to use for minting
    }

    /// Represents a single LP position (NFT) in a pool.
    struct Position has key, store {
        pool_id: u64, // Pool this position belongs to
        k_sqrt_added: u64, // Amount of liquidity provided (sqrt K)
        x_fee_growth_inside_x128: u128, // Fee growth for X at the time of mint
        y_fee_growth_inside_x128: u128, // Fee growth for Y at the time of mint
        debt_x_fee_growth_inside_x128: u128, // Fee growth for virtual X at the time of mint
        debt_y_fee_growth_inside_x128: u128, // Fee growth for virtual Y at the time of mint
        burn_ref: BurnRef, // Burn capability for the NFT
        mutator_ref: MutatorRef // Mutator capability for the NFT
    }

    // Error code for LP NFT not owned by the user
    const ERR_LP_NFT_NOT_OWNED: u64 = 1;
    // Error code for LP NFT not existing in the collection
    const ERR_LP_NFT_NOT_EXISTS: u64 = 2;

    /// Stores all LP NFT collections for all pools.
    struct CollectionMetadatas has key, store {
        metadatas: Table<u64, CollectionMetadata>, // Mapping from pool_id to CollectionMetadata
    }

    // -------------------- Initialization --------------------
    /// Initializes the position module by creating the CollectionMetadatas resource.
    fun init_module(_: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        move_to(
            &resource_signer,
            CollectionMetadatas { 
                metadatas: table::new<u64, CollectionMetadata>(),
            },
        );
    }

    // -------------------- Collection Management --------------------
    /// Creates a new LP NFT collection for a pool.
    public fun create_collection(
        pool_id: u64,
    ): (address)  acquires CollectionMetadatas {
        let resource_account = package_manager::get_resource_signer();
        let royalty = option::none();
        // Maximum supply cannot be changed after collection creation
        let lp_collection_name: string::String = string::utf8(b"CiSwap LP-");
        string::append(&mut lp_collection_name, u64_utils::u64_to_string(pool_id));
        let constructor_ref = collection::create_unlimited_collection(
            &resource_account,
            string::utf8(b"CiSwap LPs"),
            lp_collection_name,
            royalty,
            string::utf8(b"https://ciswap.finance"),
        );
        object::generate_extend_ref(&constructor_ref);

        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_account)
        );
        let collection_metadata = CollectionMetadata {
            collection_addr: object::address_from_constructor_ref(&constructor_ref),
            name: lp_collection_name,
            positions: table::new<address, Position>(),
            next_nft_id: 0 // Start with ID 0
        };
        table::add(
            &mut collection_metadatas.metadatas,
            pool_id,
            collection_metadata
        );

        object::address_from_constructor_ref(&constructor_ref)
    }   

    /// Helper to create a unique NFT name for a position.
    fun make_nft_name(pool_id: u64, next_nft_id: u64): string::String {
        let nft_name: string::String = string::utf8(b"CiSwap LP-");
        string::append(&mut nft_name, u64_utils::u64_to_string(pool_id));
        string::append(&mut nft_name, string::utf8(b"-"));
        string::append(&mut nft_name, u64_utils::u64_to_string(next_nft_id));
        nft_name
    }

    // -------------------- NFT Minting/Updating --------------------
    /// Mints a new LP NFT for a user, or updates an existing one if present.
    /// Transfers the NFT to the user.
    public fun increase_lp_nft(
        user: &signer,
        pool_id: u64,
        nft_addr: address,
        k_sqrt_added: u64,
    ) acquires CollectionMetadatas {
        let resource_account = package_manager::get_resource_signer();
        let resource_account_addr = signer::address_of(&resource_account);
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_account)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let positions = &mut collection_metadata.positions;
        // revert if the position does not contain the nft address
        assert!(
            table::contains(positions, nft_addr),
            ERR_LP_NFT_NOT_EXISTS
        );
        if (table::contains(positions, nft_addr)) {
            // If the NFT already exists, update the liquidity amount
            let position = table::borrow_mut(positions, nft_addr);
            position.k_sqrt_added = position.k_sqrt_added + k_sqrt_added;
            return;
        };
    }
    
    public fun create_then_transfer_lp_nft(
        user: &signer,
        pool_id: u64,
        k_sqrt_added: u64,
    ) : (address) acquires CollectionMetadatas {
        let resource_account = package_manager::get_resource_signer();
        let resource_account_addr = signer::address_of(&resource_account);
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_account)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let positions = &mut collection_metadata.positions;
        // Mint a new NFT position
        let royalty = option::none();
        let nft_name = make_nft_name(pool_id, collection_metadata.next_nft_id);
        let nft_constructor_ref = &token::create_named_token(
            &resource_account,
            collection_metadata.name,
            string::utf8(b"CiSwap LP NFT"),
            nft_name,
            royalty,
            string::utf8(b"https://ciswap.finance"),
        );
        let nft_addr = object::address_from_constructor_ref(nft_constructor_ref);

        let burn_ref = token::generate_burn_ref(nft_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(nft_constructor_ref);
        let position = Position {
            pool_id,
            k_sqrt_added,
            x_fee_growth_inside_x128: 0,
            y_fee_growth_inside_x128: 0,
            debt_x_fee_growth_inside_x128: 0,
            debt_y_fee_growth_inside_x128: 0,
            burn_ref,
            mutator_ref
        };
        table::add(
            positions,
            nft_addr,
            position
        );
        let created_nft_addr = token::create_token_address(
            &resource_account_addr,
            &collection_metadata.name,
            &nft_name,
        );
        let nft 
            = object::address_to_object<Token>(created_nft_addr);
        object::transfer(
            &resource_account, 
            nft, 
            signer::address_of(user)
        );
        // Update the next NFT ID for this collection
        collection_metadata.next_nft_id = collection_metadata.next_nft_id + 1;

        nft_addr
    }

    // -------------------- Ownership Assertion --------------------
    /// Asserts that a user owns a specific LP NFT for a pool.
    fun assert_lp_nft_ownership(
        user_addr: address,
        pool_id: u64,
        nft_addr: address,
        collection_name: String
    ) {
        let resource_signer = package_manager::get_resource_signer();
        // Check if the user owns the NFT
        let nft = object::address_to_object<Token>(nft_addr);
        assert!(
            object::owner(nft) == user_addr, 
            ERR_LP_NFT_NOT_OWNED
        );
    }

    // -------------------- Position Info --------------------
    /// Returns all fee and liquidity info for a user's position (LP NFT) in a pool.
    public fun get_position_info(
        pool_id: u64,
        user_addr: address,
        nft_address: address
    ): (
        u64,   // k_sqrt_added
        u128,  // x_fee_growth_inside_x128
        u128,  // y_fee_growth_inside_x128
        u128,  // x_fee_growth_inside_debt_x128
        u128,  // y_fee_growth_inside_debt_y_x128
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow(&collection_metadatas.metadatas, pool_id);
        let position = table::borrow(&collection_metadata.positions, nft_address);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_address,
            collection_metadata.name
        );
        // Return all relevant position info
        (
            position.k_sqrt_added,
            position.x_fee_growth_inside_x128,
            position.y_fee_growth_inside_x128,
            position.debt_x_fee_growth_inside_x128,
            position.debt_y_fee_growth_inside_x128,
        )
    }

    public fun update_position_fee_growth_inside(
        user_addr: address,
        pool_id: u64,
        nft_addr: address,
        updated_x_fee_growth_inside_x128: u128,
        updated_y_fee_growth_inside_x128: u128,
        updated_debt_x_fee_growth_inside_x128: u128,
        updated_debt_y_updated_fee_growth_inside_x128: u128
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_addr);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_addr,
            collection_metadata.name
        );
        // Overwrite the fee growth inside values
        position.x_fee_growth_inside_x128         = updated_x_fee_growth_inside_x128;
        position.y_fee_growth_inside_x128         = updated_y_fee_growth_inside_x128;
        position.debt_x_fee_growth_inside_x128    = updated_debt_x_fee_growth_inside_x128;
        position.debt_y_fee_growth_inside_x128    = updated_debt_y_updated_fee_growth_inside_x128;
    }

    public fun update_position_k_sqrt_added(
        user_addr: address,
        pool_id: u64,
        nft_addr: address,
        updated_k_sqrt_added: u64
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_addr);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_addr,
            collection_metadata.name
        );
        // Overwrite the k_sqrt_added value
        position.k_sqrt_added = updated_k_sqrt_added;
    }

    // ─────────────── Test Harness ───────────────
    /// Testing-only initializer for the FA module.
    #[test_only]
    public fun init_for_test() {
        init_module(&package_manager::get_resource_signer());
    }
}