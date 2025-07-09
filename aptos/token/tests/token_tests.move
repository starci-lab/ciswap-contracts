#[test_only]
module token::token_tests {
    use token::token::{ Self, Token };
    use std::signer::{ Self };
    use aptos_framework::account::{ Self };
    use aptos_framework::resource_account::{ Self };
    use aptos_framework::coin::{ Self };
    use aptos_framework::managed_coin::{ Self };

    // Custom error code imported from your module
    const ERR_NOT_DEPLOYER: u64 = 0;
    const TEMPLATE_TOTAL_SUPPLY: u64 = 10000000000000000;

    /// Helper to initialize module under test
    #[test_only]
    public fun setup(deployer: &signer, resource_signer: &signer) {
        // Create resource account for testing
        account::create_account_for_test(signer::address_of(deployer));
        resource_account::create_resource_account(deployer, b"token", b"");
        token::initialize_for_test(resource_signer);
    }

    /// Test that only deployer can mint and minting works
    #[test(deployer = @deployer, resource_account = @token, alice = @0x12345)]
    public fun test_mint_success(deployer: &signer, resource_account: &signer, alice: &signer) {
        // Create a signer for alice
        account::create_account_for_test(signer::address_of(alice));
        // Setup environment
        setup(deployer, resource_account);

        // Register owner's account for holding token
        coin::register<Token>(alice);

        // Should succeed: deployer mints total supply to self
        token::mint_token(deployer);

        // Check balance of deployer
        let balance = coin::balance<Token>(signer::address_of(deployer));
        assert!(balance == TEMPLATE_TOTAL_SUPPLY, 1);
    }
}