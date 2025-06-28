    module token::token {
        // Import necessary modules
        use aptos_framework::managed_coin::{ Self }; // Provides functionality for managing custom coins
        use std::signer::{ Self }; // For signer-related operations
        use aptos_framework::account::{ Self, SignerCapability }; // To create signers from capabilities
        use aptos_framework::resource_account::{ Self }; // To create and manage resource accounts
        use aptos_framework::coin::{ Self }; // Basic coin operations like registration, transfers, etc.

        // Define the custom token type
        // This struct acts as a phantom type for identifying our custom coin
        struct Token {}

        // Stores the capability to sign as the resource account
        // This is stored on-chain to allow authorized minting via signer creation
        struct PermissionConfig has key {
            signer_cap: SignerCapability, // Signer capability of the resource account
        }

        // Constants
        const DEPLOYER: address = @deployer; // The address that deployed the module (replace in CLI with --named-addresses)
        const RESOURCE_ACCOUNT: address = @token; // The resource account address where the token is managed
        const TEMPLATE_NAME: vector<u8> = b"UST Tether"; // The display name of the token
        const TEMPLATE_SYMBOL: vector<u8> = b"USDT"; // The symbol used for the token
        const TEMPLATE_DECIMALS: u8 = 8; // Number of decimals for the token (like 10^8)
        const TEMPLATE_TOTAL_SUPPLY: u64 = 10000000000000000; // The initial total supply to mint

        // Error codes
        const ESENDER_NOT_DEPLOYER : u64 = 0; // Error if a non-deployer tries to mint
        const ESETUP_HAS_DONE : u64 = 1; // Error if setup is called again (unused here)

        // Initializes the module and token under a resource account
        fun init_module(sender: &signer) {
            // Retrieve the signer capability to act on behalf of the resource account
            let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEPLOYER);
            // Create a signer from the signer capability
            let resource_signer = account::create_signer_with_capability(&signer_cap);
            // Initialize the managed coin with metadata
            managed_coin::initialize<Token>(
                &resource_signer,
                TEMPLATE_NAME,
                TEMPLATE_SYMBOL,
                TEMPLATE_DECIMALS,
                true // Indicates it's a fungible token
            );
            // Store the signer capability on-chain under the resource account
            move_to(
                &resource_signer,
                PermissionConfig {
                    signer_cap
                }
            ); 
        }

        // Entry function to mint tokens from the resource account
        public entry fun mint_token(sender: &signer) acquires PermissionConfig {
            // Load the PermissionConfig stored under the resource account address
            let permission_config = borrow_global_mut<PermissionConfig>(RESOURCE_ACCOUNT);
            let signer_cap = &permission_config.signer_cap;
            // Create a signer from the stored capability
            let resource_signer = account::create_signer_with_capability(signer_cap);
            // Ensure only the deployer can call this function
            assert!(signer::address_of(sender) == DEPLOYER, ESENDER_NOT_DEPLOYER);

            // If the deployer's account is not registered to hold this token, register it
            if (!coin::is_account_registered<Token>(signer::address_of(sender))) {
                coin::register<Token>(sender);
            };

            // Mint the total supply to the deployer's account
            managed_coin::mint<Token>(
                &resource_signer,
                signer::address_of(sender), // receiver of the tokens
                TEMPLATE_TOTAL_SUPPLY
            );
        }

        // Test-only initializer to help set up the module in unit tests
        #[test_only]
        public fun initialize_for_test(resource_signer: &signer) {
            init_module(resource_signer); // Simulate real init during testing
        }
    }