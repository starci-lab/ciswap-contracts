module ciswap::fa_utils {
    //! ===============================================================
    //! ciswap::fa_utils
    //! ---------------------------------------------------------------
    //! Utilities for wrapping legacy `coin<T>` tokens into the new
    //! object-based `fungible_asset` standard. Also handles on-chain
    //! permissioning for minting, burning, and transferring FA tokens.
    //! ===============================================================

    // ─────────────── Imports ───────────────
    use std::signer::{Self};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        MintRef,
        BurnRef,
        TransferRef,
        Metadata,
        FungibleStore
    };
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store::{Self};
    use aptos_framework::option::{Self};
    use aptos_framework::table::{Self, Table};
    use ciswap::package_manager::{Self};
    use aptos_framework::string::{String};

    const RESOURCE_ACCOUNT: address = @ciswap;

    // ─────────────── Simple Coin → FA Wrapper ───────────────
    /// Converts a legacy `coin<T>` into a `FungibleAsset` object.
    /// No mint/burn authority is created — this is a simple wrapper.
    public fun wrap<T>(coin: Coin<T>): FungibleAsset {
        coin::coin_to_fungible_asset(coin)
    }

    // ─────────────── Permission Structs ───────────────
    /// Holds mint / burn / transfer capabilities for a fungible asset.
    struct FAPermission has key, store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /// Top-level permission registry mapping FA address → FAPermission.
    /// Each FA instance stores its own permission table at its address.
    struct FAPermissions has key, store {
        permissions: Table<address, FAPermission>,
    }

    // ─────────────── Module Initialization ───────────────
    /// Called once by the package manager to initialize the empty
    /// permissions table under the FA resource account.
    fun init_module(_: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        let permissions = table::new<address, FAPermission>();
        move_to(&resource_signer, FAPermissions { permissions });
    }

    // ─────────────── Create FA ───────────────
    /// Deploys a new fungible asset with metadata and stores mint/burn/transfer permissions.
    /// Returns the address of the new FA object.
    public fun create_fungible_asset(
        resource_signer: &signer,
        salt: vector<u8>,     // deterministic seed for address
        name: String,          // e.g. "USD Coin"
        symbol: String,        // e.g. "USDC"
        icon_uri: String,      // URL to token icon
        project_uri: String    // project homepage
    ): address acquires FAPermissions {
        // Step 1: Create named object (temporary holder)
        let constructor_ref = &object::create_named_object(resource_signer, salt);

        // Step 2: Create a fungible asset with 8 decimals and store support
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(), // No aggregator
            name,
            symbol,
            8,              // 8 decimal precision
            icon_uri,
            project_uri
        );

        // Step 3: Extract the final address of the FA object
        let fa_addr = object::address_from_constructor_ref(constructor_ref);

        // Step 4: Generate mint/burn/transfer capability references
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        // Step 5: Save those permissions into the FA's on-chain permission table
        let permissions = &mut borrow_global_mut<FAPermissions>(signer::address_of(resource_signer)).permissions;
        let permission = FAPermission { mint_ref, burn_ref, transfer_ref };
        table::add(permissions, fa_addr, permission);

        fa_addr
    }

    // ─────────────── Mint ───────────────
    // Mints `amount` of a given FA using its stored mint capability.
    public fun mint(fa_address: address, amount: u64): FungibleAsset acquires FAPermissions {
        let permissions = &borrow_global<FAPermissions>(RESOURCE_ACCOUNT).permissions;
        let permission = table::borrow(permissions, fa_address);
        fungible_asset::mint(&permission.mint_ref, amount)
    }

    // ─────────────── Burn ───────────────
    // Burns a `FungibleAsset` using its stored burn capability.
    public fun burn(asset: FungibleAsset) acquires FAPermissions {
        let metadata = fungible_asset::metadata_from_asset(&asset);
        let fa_address = object::object_address(&metadata);
        let permissions = &borrow_global<FAPermissions>(RESOURCE_ACCOUNT).permissions;
        let permission = table::borrow(permissions, fa_address);
        fungible_asset::burn(&permission.burn_ref, asset);
    }

    // ─────────────── Create Store ───────────────
    // Registers a new account to hold a specific FA by creating a store.
    public fun create_store(owner: &signer, fa_address: address): Object<FungibleStore> {
        fungible_asset::create_store(
            &object::create_object_from_account(owner),
            get_metadata(fa_address),
        )
    }

    // ─────────────── Withdraw ───────────────
    // Withdraws `amount` from a user's FA balance into a standalone asset object.
    public fun withdraw_fa_from_address(
        owner: &signer,
        account_address: address,
        fa_address: address,
        amount: u64
    ): FungibleAsset {
        let metadata = object::address_to_object<Metadata>(fa_address);
        primary_fungible_store::withdraw(owner, metadata, amount)
    }

    // ─────────────── Balance Query ───────────────
    /// Returns the current balance of a user for a specific FA.
    public fun balance_of(account_address: address, fa_address: address): u64 {
        let metadata = object::address_to_object<Metadata>(fa_address);
        primary_fungible_store::balance(account_address, metadata)
    }

    // ─────────────── Internal: Fetch Metadata ───────────────
    // Loads the metadata object of an FA from its address.
    public fun get_metadata(fa_address: address): Object<Metadata> {
        object::address_to_object<Metadata>(fa_address)
    }

    // ─────────────── Test Harness ───────────────
    // In testing mode, initializes the FA module under a test signer.
    #[test_only]
    public fun init_for_test() {
        init_module(&package_manager::get_resource_signer());
    }
}
