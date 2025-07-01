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

    struct CollectionMetadata has key, store {
        name: String,
        next_nft_id: u64,
        positions: Table<u64, Position>,
    }

    struct Position has key, store {
        pool_id: u64,
        k_sqrt_added: u64,
        fee_growth_inside_x: u128,
        fee_growth_inside_y: u128,
        fee_growth_inside_debt_x: u128,
        fee_growth_inside_debt_y: u128,
        fee_owed_x: u64,
        fee_owed_y: u64,
        fee_owed_debt_x: u64,
        fee_owed_debt_y: u64,
        burn_ref: BurnRef,
        mutator_ref: MutatorRef
    }

    const ERR_LP_NFT_NOT_OWNED: u64 = 0x1;

    struct CollectionMetadatas has key, store {
        metadatas: Table<u64, CollectionMetadata>,
    }

    /// Initializes the package manager module exactly once
    fun init_module(_: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        move_to(
            &resource_signer,
            CollectionMetadatas { 
                metadatas: table::new<u64, CollectionMetadata>(),
            },
        );
    }

    public fun create_collection(
        pool_id: u64,
    )  acquires CollectionMetadatas {
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
            name: lp_collection_name,
            next_nft_id: 0,
            positions: table::new<u64, Position>(),
        };
        table::add(
            &mut collection_metadatas.metadatas,
            pool_id,
            collection_metadata
        );
    }   

    fun make_nft_name(pool_id: u64, next_nft_id: u64): string::String {
        let nft_name: string::String = string::utf8(b"CiSwap LP-");
        string::append(&mut nft_name, u64_utils::u64_to_string(pool_id));
        string::append(&mut nft_name, string::utf8(b"-"));
        string::append(&mut nft_name, u64_utils::u64_to_string(next_nft_id));
        nft_name
    }

    public fun create_then_transfer_or_update_lp_nft(
        user: &signer,
        pool_id: u64,
        k_sqrt_added: u64,
    ) acquires CollectionMetadatas {
        let resource_account = package_manager::get_resource_signer();
        let resource_account_addr = signer::address_of(&resource_account);
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_account)
        );
        // Check if the collection exists, if not, create it
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let positions = &mut collection_metadata.positions;
        if (table::contains(positions, collection_metadata.next_nft_id)) {
            // update the existing position
            let position = table::borrow_mut(positions, collection_metadata.next_nft_id);
            position.k_sqrt_added = position.k_sqrt_added + k_sqrt_added;
            return;
        };
        // create a new position
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

        let burn_ref = token::generate_burn_ref(nft_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(nft_constructor_ref);
        let position = Position {
            pool_id,
            k_sqrt_added,
            fee_growth_inside_x: 0,
            fee_growth_inside_y: 0,
            fee_growth_inside_debt_x: 0,
            fee_growth_inside_debt_y: 0,
            fee_owed_x: 0,
            fee_owed_y: 0,
            fee_owed_debt_x: 0,
            fee_owed_debt_y: 0,
            burn_ref,
            mutator_ref
        };
        table::add(
            positions,
            collection_metadata.next_nft_id,
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
        // transfer the NFT to the user
        collection_metadata.next_nft_id = collection_metadata.next_nft_id + 1;
    }

    fun assert_lp_nft_ownership(
        user_addr: address,
        pool_id: u64,
        nft_id: u64,
        collection_name: String
    ) {
        let resource_signer = package_manager::get_resource_signer();
        // Check if the user owns the NFT
        let nft_address = token::create_token_address(
            &signer::address_of(&resource_signer),
            &collection_name,
            &make_nft_name(pool_id, nft_id)
        );
        let nft = object::address_to_object<Token>(nft_address);
        assert!(
            object::owner(nft) == user_addr, 
            ERR_LP_NFT_NOT_OWNED
        );
    }

    public fun get_position_info(
        user_addr: address,
        pool_id: u64,
        nft_id: u64
    ): (
        u64,   // k_sqrt_added
        u128,  // fee_growth_inside_x
        u128,  // fee_growth_inside_y
        u128,  // fee_growth_inside_debt_x
        u128,  // fee_growth_inside_debt_y
        u64,   // fee_owed_x
        u64,   // fee_owed_y
        u64,   // fee_owed_debt_x
        u64    // fee_owed_debt_y
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow(&collection_metadatas.metadatas, pool_id);
        let position = table::borrow(&collection_metadata.positions, nft_id);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_id,
            collection_metadata.name
        );
        // Overwrite the fee owed values
        (
            position.k_sqrt_added,
            position.fee_growth_inside_x,
            position.fee_growth_inside_y,
            position.fee_growth_inside_debt_x,
            position.fee_growth_inside_debt_y,
            position.fee_owed_x,
            position.fee_owed_y,
            position.fee_owed_debt_x,
            position.fee_owed_debt_y
        )
    }

    public fun update_position_fee_owed(
        user_addr: address,
        pool_id: u64,
        nft_id: u64,
        updated_k_sqrt_added: u64,
        updated_fee_owed_x: u64,
        updated_fee_owed_y: u64,
        updated_fee_owed_debt_x: u64,
        updated_fee_owed_debt_y: u64
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_id);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_id,
            collection_metadata.name
        );
        // Overwrite the fee owed values
        position.fee_owed_x                 = updated_fee_owed_x;
        position.fee_owed_y                 = updated_fee_owed_y;
        position.fee_owed_debt_x            = updated_fee_owed_debt_x;
        position.fee_owed_debt_y            = updated_fee_owed_debt_y;
    }

    public fun update_position_fee_growth_inside(
        user_addr: address,
        pool_id: u64,
        nft_id: u64,
        updated_fee_growth_inside_x: u128,
        updated_fee_growth_inside_y: u128,
        updated_fee_growth_inside_debt_x: u128,
        updated_fee_growth_inside_debt_y: u128
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_id);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_id,
            collection_metadata.name
        );
        // Overwrite the fee growth inside values
        position.fee_growth_inside_x         = updated_fee_growth_inside_x;
        position.fee_growth_inside_y         = updated_fee_growth_inside_y;
        position.fee_growth_inside_debt_x    = updated_fee_growth_inside_debt_x;
        position.fee_growth_inside_debt_y    = updated_fee_growth_inside_debt_y;
    }

    public fun update_position_k_sqrt_added(
        user_addr: address,
        pool_id: u64,
        nft_id: u64,
        updated_k_sqrt_added: u64
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_id);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_id,
            collection_metadata.name
        );
        // Overwrite the k_sqrt_added value
        position.k_sqrt_added = updated_k_sqrt_added;
    }

    public fun reset_position_fee_owed(
        user_addr: address,
        pool_id: u64,
        nft_id: u64
    ) acquires CollectionMetadatas {
        let resource_signer = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_signer)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let position = table::borrow_mut(&mut collection_metadata.positions, nft_id);
        assert_lp_nft_ownership(
            user_addr,
            pool_id,
            nft_id,
            collection_metadata.name
        );
        // Overwrite the fee owed values to zero
        position.fee_owed_x                 = 0;
        position.fee_owed_y                 = 0;
        position.fee_owed_debt_x            = 0;
        position.fee_owed_debt_y            = 0;
    }

    // ─────────────── Test Harness ───────────────
    /// Testing-only initializer for the FA module.
    #[test_only]
    public fun init_for_test() {
        init_module(&package_manager::get_resource_signer());
    }
}