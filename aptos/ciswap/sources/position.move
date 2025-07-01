module ciswap::position {
    //! Converts legacy `coin<T>` tokens into their object-based `fungible_asset` equivalents
    use std::signer::{ Self };
    use aptos_framework::coin::{ Self, Coin };
    use aptos_framework::fungible_asset::{ Self, FungibleAsset, Metadata };
    use aptos_token_objects::collection::{ Self };
    use aptos_token_objects::token::{ Self, Token };
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
    }

    struct Position has key, store {
        pool_id: u64,
        nft_id: u64,
        k_sqrt_added: u64,
        fee_growth_inside_x: u64,
        fee_growth_inside_y: u64,
        tokens_owed_x: u64,
        tokens_owed_y: u64,
    }

    struct CollectionMetadatas has key, store {
        metadatas: Table<u64, CollectionMetadata>,
        positions: Table<u64, Position>,
    }

    /// Initializes the package manager module exactly once
    fun init_module(sender: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        move_to(
            &resource_signer,
            CollectionMetadatas { 
                metadatas: table::new<u64, CollectionMetadata>(),
                positions: table::new<u64, Position>(),
            },
        );
    }

    public fun create_collection(
        pool_id: u64,
    ) {
        let resource_account = package_manager::get_resource_signer();
        let royalty = option::none();
        // Maximum supply cannot be changed after collection creation
        let lp_collection_name: string::String = string::utf8(b"CiSwap-LP-");
        string::append(&mut lp_collection_name, u64_utils::u64_to_string(pool_id));
        collection::create_unlimited_collection(
            &resource_account,
            string::utf8(b"CiSwap LPs"),
            lp_collection_name,
            royalty,
            string::utf8(b"https://ciswap.finance"),
        );
    }   

    public fun create_lp_nft(
        user: &signer,
        pool_id: u64,
        k_sqrt_added: u64,
    ) {
        let resource_account = package_manager::get_resource_signer();
        let collection_metadatas = borrow_global_mut<CollectionMetadatas>(
            signer::address_of(&resource_account)
        );
        let collection_metadata = table::borrow_mut(&mut collection_metadatas.metadatas, pool_id);
        let royalty = option::none();
        let nft_constructor_ref = &token::create(
            &resource_account,
            collection_metadata.name,
            string::utf8(b"CiSwap LP NFT"),
            string::utf8(b"CiSwap LP NFT"),
            royalty,
            string::utf8(b"https://ciswap.finance"),
        );
        let position = Position {
            pool_id,
            nft_id: collection_metadata.next_nft_id,
            k_sqrt_added,
            fee_growth_inside_x: 0,
            fee_growth_inside_y: 0,
            tokens_owed_x: 0,
            tokens_owed_y: 0,
        };
        table::add(
            &mut collection_metadatas.positions,
            collection_metadata.next_nft_id,
            position
        );
        // transfer the NFT to the user
    }
}