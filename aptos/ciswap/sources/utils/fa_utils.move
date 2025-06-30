module ciswap::fa_utils {
    //! Converts legacy `coin<T>` tokens into their object-based `fungible_asset` equivalents
    use std::signer::{ Self };
    use aptos_framework::coin::{ Self, Coin };
    use aptos_framework::fungible_asset::{ 
        Self, 
        FungibleAsset, 
        MintRef, 
        BurnRef, 
        TransferRef, 
        Metadata, 
        FungibleStore
    };
    use aptos_framework::object::{ Self, ConstructorRef, Object };
    use aptos_framework::primary_fungible_store::{ Self };
    use aptos_framework::option::{ Self };
    use aptos_framework::string::{ Self };
    use aptos_framework::table::{ Self, Table };
    use ciswap::package_manager::{ Self };
    use aptos_std::type_info::{Self};
    use aptos_framework::string::{ String };
    /// Wraps a `coin<T>` into a `fungible_asset` object
    public fun wrap<T>(coin: Coin<T>): FungibleAsset {
        coin::coin_to_fungible_asset(coin)
    }

    struct FAPermission has key, store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }   

    struct FAPermissions has key, store {
        permissions: Table<address, FAPermission>,
    }

    fun init_module(_: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        // Initialize the module with an empty permissions table
        let permissions = table::new<address, FAPermission>();
        move_to(&resource_signer, FAPermissions { permissions });
    }

    // Create a fungible asset
    public fun create_fungible_asset(
        resource_signer: &signer,
        salt: vector<u8>,
        name: String,
        symbol: String,
        icon_uri: String,
        project_uri: String
    ): (address) acquires FAPermissions {
        let constructor_ref = &object::create_named_object(
            resource_signer, 
            salt
        );
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol,
            8,
            icon_uri,
            project_uri,
        );

        let constructor_ref_address = object::address_from_constructor_ref(constructor_ref);
 
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        let permissions = &mut borrow_global_mut<FAPermissions>(
            constructor_ref_address
        ).permissions;

        let permission = FAPermission {
            mint_ref,
            burn_ref,
            transfer_ref
        };

 
        // Store the permission in the table using the address as key
        table::add(permissions, constructor_ref_address, permission);

        // Return the address of the fungible asset
        constructor_ref_address
    }

    public fun mint(
        fa_address: address, 
        amount: u64
    ): FungibleAsset acquires FAPermissions {
        let permissions = &borrow_global<FAPermissions>(fa_address).permissions;
        let permission = table::borrow(permissions, fa_address);
        let fa = fungible_asset::mint(
            &permission.mint_ref,
            amount,
        );
        // return the permissioned fungible asset
        fa
    }

    public fun create_store(
        owner: &signer,
        fa_address: address
    ): Object<FungibleStore> {
        // Create a primary store for the fungible asset
        fungible_asset::create_store(
            &object::create_object_from_account(owner),
            get_metadata(
                fa_address
            ),
        )
    }

    public fun withdraw_fa_from_address(
        owner: &signer,
        account_address: address,
        amount: u64
    ): FungibleAsset {
        let store = object::address_to_object<FungibleStore>(account_address);
        fungible_asset::withdraw(owner, store, amount)
    }

    public fun get_metadata(fa_address: address): Object<Metadata> {
        object::address_to_object<Metadata>(fa_address)
    }
}