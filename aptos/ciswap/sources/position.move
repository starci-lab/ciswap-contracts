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
        fee_growth_inside_x: u64,
        fee_growth_inside_y: u64,
        tokens_owed_x: u64,
        tokens_owed_y: u64,
        burn_ref: BurnRef,
        mutator_ref: MutatorRef
    }

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
        let nft_name: string::String = string::utf8(b"CiSwap LP-");
        string::append(&mut nft_name, u64_utils::u64_to_string(pool_id));
        string::append(&mut nft_name, string::utf8(b"-"));
        string::append(&mut nft_name, u64_utils::u64_to_string(collection_metadata.next_nft_id));
        
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
            tokens_owed_x: 0,
            tokens_owed_y: 0,
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

    // ─────────────── Test Harness ───────────────
    /// Testing-only initializer for the FA module.
    #[test_only]
    public fun init_for_test() {
        init_module(&package_manager::get_resource_signer());
    }
}