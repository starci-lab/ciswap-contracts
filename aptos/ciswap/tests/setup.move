#[test_only]
module ciswap::setup {
    //! ============================================================
    //! ciswap::setup
    //! ------------------------------------------------------------
    //! This module provides a one-time setup function for the CiSwap
    //! package manager and fungible asset utilities, ensuring a clean
    //! state for testing.
    //! ============================================================
    use aptos_framework::account::{Self};
    use aptos_framework::genesis::{Self};
    use ciswap::package_manager::{Self};
    use ciswap::fa_utils::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::coin::{Self};

    // ─────────────── Module‑wide constants ───────────────
    const DEPLOYER: address = @deployer;
    const DEFAULT_ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @ciswap;
    const APTOS_FRAMEWORK: address = @aptos_framework;
    // ─────────────── One-time setup function ───────────────
    public fun setup() {
        genesis::setup();
        let deployer = account::create_account_for_test(DEPLOYER);
        account::create_account_for_test(DEFAULT_ADMIN);
        let aptos_framework = account::create_account_for_test(APTOS_FRAMEWORK);
        coin::create_coin_conversion_map(&aptos_framework);
        resource_account::create_resource_account(
            &deployer,
            b"ciswap",
            b""
        );
        package_manager::init_for_test();
        fa_utils::init_for_test();
        
    }
}