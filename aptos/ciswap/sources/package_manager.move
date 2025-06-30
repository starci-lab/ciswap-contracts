// ===============================================
//  CiSwap Package Manager Module
//  ----------------------------------------------
//  Manages the signer capability for secure package upgrades
// ===============================================

module ciswap::package_manager {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account::{Self};
    use std::signer;

    // ──────────────── Constants ────────────────
    const DEPLOYER: address = @deployer;
    const RESOURCE_ACCOUNT: address = @ciswap;

    // ──────────────── Error Codes ────────────────
    const ENOT_DEPLOYER: u64 = 1;       // Sender is not the deployer
    const EALREADY_INITIALIZED: u64 = 2; // Module already initialized
    const ENOT_RESOURCE_ACCOUNT: u64 = 3; // Invalid resource account
    const ECAPABILITY_NOT_FOUND: u64 = 4; // Signer capability not found

    // ──────────────── Resources ────────────────
    struct PermissionConfig has key {
        signer_cap: SignerCapability,
    }

    // ──────────────── Initialization ────────────────
    /// Initializes the package manager module exactly once
    fun init_module(sender: &signer) {
        // Check not already initialized
        assert!(!exists<PermissionConfig>(RESOURCE_ACCOUNT), EALREADY_INITIALIZED);
        // Retrieve and store the signer capability
        let signer_cap = resource_account::retrieve_resource_account_cap(
            sender,
            DEPLOYER,
        );
        // Verify correct resource account
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        assert!(signer::address_of(&resource_signer) == RESOURCE_ACCOUNT, ENOT_RESOURCE_ACCOUNT);

        move_to(
            &resource_signer,
            PermissionConfig { signer_cap },
        );
    }

    // ──────────────── Access Control ────────────────
    /// Retrieves the signer capability for authorized upgrades
    public fun get_resource_signer(): signer acquires PermissionConfig {
        // Load the PermissionConfig resource
        let permission_config = borrow_global_mut<PermissionConfig>(RESOURCE_ACCOUNT);  
        account::create_signer_with_capability(&permission_config.signer_cap)
    }

    // ──────────────── View Functions ────────────────
    /// Returns whether the module has been initialized
    #[view]
    public fun is_initialized(): bool {
        exists<PermissionConfig>(RESOURCE_ACCOUNT)
    }

    #[test_only]
    public fun initialize(sender: &signer) {
        init_module(sender);
    }
}