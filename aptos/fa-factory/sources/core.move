    module fa_factory::core {
        // Import necessary modules
        use aptos_framework::managed_coin::{ Self }; // Provides functionality for managing custom coins
        use std::signer::{ Self }; // For signer-related operations
        use aptos_framework::account::{ Self, SignerCapability }; // To create signers from capabilities
        use aptos_framework::resource_account::{ Self }; // To create and manage resource accounts
        use aptos_framework::coin::{ Self }; // Basic coin operations like registration, transfers, etc.
        use aptos_framework::fungible_asset::{ Self, FungibleStore, Metadata, FungibleAsset };
        use aptos_framework::primary_fungible_store::{ Self }; // For primary fungible asset management
        use aptos_framework::object::{ Self }; // For object management
        use aptos_framework::option::{ Self }; // For optional values
        use aptos_framework::string::{ Self }; // For string operations
        use fa_factory::package_manager::{ Self }; // For package management and signer capabilities

        // Constants
        const DEPLOYER: address = @deployer; // The address that deployed the module (replace in CLI with --named-addresses)
        const RESOURCE_ACCOUNT: address = @fa_factory; // The resource account address where the token is managed

        // Error codes
        const ESENDER_NOT_DEPLOYER : u64 = 0; // Error if a non-deployer tries to mint
        const ESETUP_HAS_DONE : u64 = 1; // Error if setup is called again (unused here)

        struct FAPermission has key, store {
            mint_ref: fungible_asset::MintRef,
            burn_ref: fungible_asset::BurnRef,
            transfer_ref: fungible_asset::TransferRef,
        }

        // Entry function to mint tokens from the resource account
        public entry fun create_then_mint(
            sender: &signer, 
            seed: vector<u8>, 
            name: vector<u8>, 
            symbol: vector<u8>, 
            decimals: u8, 
            total_supply: u64, 
            icon_uri: vector<u8>, 
            project_uri: vector<u8>,
            to_addr: address
        ) acquires FAPermission {
            let resource_signer = package_manager::get_resource_signer();
            // Step 1: Create a temporary object used to deterministically derive the FA address.
            let constructor_ref = &object::create_named_object(&resource_signer, seed);
            
            // Step 2: Extract the final address for the new fungible asset.
            let fa_addr = object::address_from_constructor_ref(constructor_ref);

            // Step 4: Create the fungible asset with 8 decimals and primary store support.
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                constructor_ref,
                option::none(),
                string::utf8(name),
                string::utf8(symbol),
                decimals,
                string::utf8(icon_uri),
                string::utf8(project_uri)
            );

            // Step 5: Generate mint, burn, and transfer capability references.
            let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
            let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
            let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

            move_to(
                &resource_signer,
                FAPermission {
                    mint_ref,
                    burn_ref,
                    transfer_ref,
                }
            );
            let fa_permission = borrow_global<FAPermission>(RESOURCE_ACCOUNT);
            let mint_ref = &fa_permission.mint_ref;
            let fa = fungible_asset::mint(
                mint_ref,
                total_supply
            );
            primary_fungible_store::deposit(
                signer::address_of(sender),
                fa
            );
        }
    }