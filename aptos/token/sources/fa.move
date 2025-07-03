    module token::fa {
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
        use token::package_manager::{ Self }; // For package management and signer capabilities

        // Constants
        const DEPLOYER: address = @deployer; // The address that deployed the module (replace in CLI with --named-addresses)
        const RESOURCE_ACCOUNT: address = @token; // The resource account address where the token is managed
        const TEMPLATE_NAME: vector<u8> = b"Scallop"; // The display name of the token
        const TEMPLATE_SYMBOL: vector<u8> = b"SCA"; // The symbol used for the token
        const TEMPLATE_ICON_URI: vector<u8> = b"https://s2.coinmarketcap.com/static/img/coins/64x64/29679.png"; // Icon URI for the token
        const TEMPLATE_PROJECT_URI: vector<u8> = b"https://scallop.io/"; //
        const TEMPLATE_DECIMALS: u8 = 8; // Number of decimals for the token (like 10^8)
        const TEMPLATE_TOTAL_SUPPLY: u64 = 10000000000000000; // The initial total supply to mint

        // Error codes
        const ESENDER_NOT_DEPLOYER : u64 = 0; // Error if a non-deployer tries to mint
        const ESETUP_HAS_DONE : u64 = 1; // Error if setup is called again (unused here)

        // Initializes the module and token under a resource account
        fun init_module(sender: &signer) {
            let resource_signer = package_manager::get_resource_signer();
            // Step 1: Create a temporary object used to deterministically derive the FA address.
            let constructor_ref = &object::create_named_object(&resource_signer, b"Scallop");
            
            // Step 2: Extract the final address for the new fungible asset.
            let fa_addr = object::address_from_constructor_ref(constructor_ref);

            // Step 4: Create the fungible asset with 8 decimals and primary store support.
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                constructor_ref,
                option::none(),
                string::utf8(TEMPLATE_NAME),
                string::utf8(TEMPLATE_SYMBOL),
                8,
                string::utf8(TEMPLATE_ICON_URI),
                string::utf8(TEMPLATE_PROJECT_URI)
            );

            // Step 5: Generate mint, burn, and transfer capability references.
            let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
            let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
            let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

            // Mint to 0x87f1da98a1a93ea7e1c1e0e026d5cc39d1a5b92955ee230325188332d2b7390a
            let fa = fungible_asset::mint(
                &mint_ref,
                TEMPLATE_TOTAL_SUPPLY
            );
            primary_fungible_store::deposit(
                @to_addr, // The address to mint the total supply to
                fa
            );
        }

        // Test-only initializer to help set up the module in unit tests
        #[test_only]
        public fun initialize_for_test(resource_signer: &signer) {
            init_module(resource_signer); // Simulate real init during testing
        }
    }