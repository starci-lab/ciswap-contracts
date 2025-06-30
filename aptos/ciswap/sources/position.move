module ciswap::position {
    //! Converts legacy `coin<T>` tokens into their object-based `fungible_asset` equivalents
    use std::signer::{ Self };
    use aptos_framework::coin::{ Self, Coin };
    use aptos_framework::fungible_asset::{ Self, FungibleAsset, Metadata };
    use aptos_token_objects::collection::{ Self };
    use aptos_framework::string::{ Self };
    use std::option::{Self, Option};
    use ciswap::u64_utils::{ Self };
    use ciswap::fa_utils::{ Self };
    use aptos_framework::object::{ Self, ConstructorRef };

    public fun create_collection(
        resource_account: &signer,
        pool_id: u64,
    ) {
        let royalty = option::none();
        // Maximum supply cannot be changed after collection creation
        let lp_collection_name: string::String = string::utf8(b"CiSwap-LP-");
        string::append(&mut lp_collection_name, u64_utils::u64_to_string(pool_id));
        collection::create_unlimited_collection(
            resource_account,
            lp_collection_name,
            string::utf8(b"CiSwap LPs"),
            royalty,
            string::utf8(b"https://ciswap.finance"),
        );
    }   
}