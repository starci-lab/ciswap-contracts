// ===============================================
//  CiSwap Package Manager Module
//  ----------------------------------------------
//  Manages the signer capability for secure package upgrades
// ===============================================

// This module manages the resource account's signer capability, allowing secure upgrades and access control for the CiSwap protocol.
module ciswap::package_manager {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account::{Self};
    use std::signer;

    // -------------------- Constants --------------------
    // The deployer address (who can initialize the module)
    const DEPLOYER: address = @deployer;
    // The resource account address for the CiSwap protocol
    const RESOURCE_ACCOUNT: address = @ciswap;

    // -------------------- Error Codes --------------------
    // Error if the sender is not the deployer
    const ENOT_DEPLOYER: u64 = 1;       // Sender is not the deployer
    // Error if the module is already initialized
    const EALREADY_INITIALIZED: u64 = 2; // Module already initialized
    // Error if the resource account is invalid
    const ENOT_RESOURCE_ACCOUNT: u64 = 3; // Invalid resource account
    // Error if the signer capability is not found
    const ECAPABILITY_NOT_FOUND: u64 = 4; // Signer capability not found

    // -------------------- Resources --------------------
    /// Stores the signer capability for the resource account.
    struct PermissionConfig has key {
        signer_cap: SignerCapability,
    }

    // -------------------- Initialization --------------------
    /// Initializes the package manager module exactly once.
    /// Stores the signer capability for the resource account.
    fun init_module(sender: &signer) {
        // Check not already initialized
        assert!(!exists<PermissionConfig>(RESOURCE_ACCOUNT), EALREADY_INITIALIZED);
        // Retrieve and store the signer capability from the deployer
        let signer_cap = resource_account::retrieve_resource_account_cap(
            sender,
            DEPLOYER,
        );
        // Verify correct resource account
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        assert!(signer::address_of(&resource_signer) == RESOURCE_ACCOUNT, ENOT_RESOURCE_ACCOUNT);

        // Store the signer capability in the resource account
        move_to(
            &resource_signer,
            PermissionConfig { signer_cap },
        );
    }

    // -------------------- Access Control --------------------
    /// Retrieves the signer capability for authorized upgrades.
    /// Only callable by the resource account.
    public fun get_resource_signer(): signer acquires PermissionConfig {
        // Load the PermissionConfig resource
        let permission_config = borrow_global_mut<PermissionConfig>(RESOURCE_ACCOUNT);  
        account::create_signer_with_capability(&permission_config.signer_cap)
    }

    // -------------------- View Functions --------------------
    /// Returns whether the module has been initialized.
    #[view]
    public fun is_initialized(): bool {
        exists<PermissionConfig>(RESOURCE_ACCOUNT)
    }

    // -------------------- Test Initialization --------------------
    /// Test-only: Initializes the module for testing purposes.
    #[test_only]
    public fun init_for_test() {
        let resource_signer = account::create_signer_for_test(RESOURCE_ACCOUNT);
        // create a test signer capability
        init_module(&resource_signer);
    }
}