module ciswap::fa_utils {
    //! ===============================================================
    //! Module: ciswap::fa_utils
    //! ---------------------------------------------------------------
    //! Utilities for wrapping legacy `coin<T>` tokens into the new
    //! object-based `fungible_asset` standard. Also handles on-chain
    //! permissioning for minting, burning, and transferring FA tokens.
    //! ===============================================================

    // ─────────────── Imports ───────────────
    use std::signer::{Self};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{
        Self, FungibleAsset, MintRef, BurnRef, TransferRef, Metadata, FungibleStore
    };
    use aptos_framework::object::{Self, Object, ObjectCore};
    use aptos_framework::primary_fungible_store::{Self};
    use aptos_framework::option::{Self};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::string::{String};
    use ciswap::package_manager::{Self};

    // ─────────────── Constants ───────────────
    const RESOURCE_ACCOUNT: address = @ciswap;

    // ─────────────── Permission Structs ───────────────
    /// Stores mint/burn/transfer capabilities for a fungible asset.
    struct FAPermission has key, store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /// Global mapping of FA address -> FAPermission.
    struct FAPermissions has key, store {
        permissions: Table<address, FAPermission>,
    }

    // ─────────────── Coin<T> to FA Wrapper ───────────────
    /// Converts a legacy `coin<T>` into a `FungibleAsset` object.
    /// No mint/burn authority is created — this is a simple wrapper.
    public fun wrap<T>(coin: Coin<T>): FungibleAsset {
        coin::coin_to_fungible_asset(coin)
    }

    // ─────────────── Module Initialization ───────────────
    /// Initializes the module by creating a permission registry under the FA resource account.
    fun init_module(_: &signer) {
        let resource_signer = package_manager::get_resource_signer();
        let permissions = table::new<address, FAPermission>();
        move_to(&resource_signer, FAPermissions { permissions });
    }

    // ─────────────── Create New Fungible Asset ───────────────
    /// Creates a new fungible asset with metadata and stores the associated permissions.
    public fun create_fungible_asset(
        resource_signer: &signer,
        seed: vector<u8>,
        name: String,
        symbol: String,
        icon_uri: String,
        project_uri: String
    ): address acquires FAPermissions {
        let resource_signer_addr = signer::address_of(resource_signer);
        let obj_addr = object::create_object_address(&resource_signer_addr, seed);
        if (object::is_object(obj_addr)) {
            return obj_addr;
        };
        // Step 1: Create a temporary object used to deterministically derive the FA address.
        let constructor_ref = &object::create_named_object(resource_signer, seed);
        
        // Step 2: Extract the final address for the new fungible asset.
        let fa_addr = object::address_from_constructor_ref(constructor_ref);

        // Step 4: Create the fungible asset with 8 decimals and primary store support.
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol,
            8,
            icon_uri,
            project_uri
        );

        // Step 5: Generate mint, burn, and transfer capability references.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        // Step 6: Store these capabilities in the on-chain permission table.
        let permissions = &mut borrow_global_mut<FAPermissions>(RESOURCE_ACCOUNT).permissions;
        let permission = FAPermission { mint_ref, burn_ref, transfer_ref };
        table::add(permissions, fa_addr, permission);

        fa_addr
    }

    // ─────────────── Mint ───────────────
    /// Mints `amount` of a given FA using its stored mint capability.
    public fun mint(fa_address: address, amount: u64): FungibleAsset acquires FAPermissions {
        let permissions = &borrow_global<FAPermissions>(RESOURCE_ACCOUNT).permissions;
        let permission = table::borrow(permissions, fa_address);
        fungible_asset::mint(&permission.mint_ref, amount)
    }

    // ─────────────── Burn ───────────────
    /// Burns a `FungibleAsset` using its stored burn capability.
    public fun burn(asset: FungibleAsset) acquires FAPermissions {
        let metadata = fungible_asset::metadata_from_asset(&asset);
        let fa_address = object::object_address(&metadata);
        let permissions = &borrow_global<FAPermissions>(RESOURCE_ACCOUNT).permissions;
        let permission = table::borrow(permissions, fa_address);
        fungible_asset::burn(&permission.burn_ref, asset);
    }

    // ─────────────── Create Store ───────────────
    /// Registers a user account to hold a given FA by creating a store.
    public fun create_store(owner: &signer, fa_address: address): Object<FungibleStore> {
        fungible_asset::create_store(
            &object::create_object_from_account(owner),
            get_metadata(fa_address)
        )
    }

    // ─────────────── Withdraw ───────────────
    /// Withdraws `amount` from a user's FA balance and returns it as a `FungibleAsset` object.
    public fun withdraw_fa_from_address(
        owner: &signer,
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
    /// Helper function to load an FA's metadata object from its address.
    public fun get_metadata(fa_address: address): Object<Metadata> {
        object::address_to_object<Metadata>(fa_address)
    }

    public fun get_address_from_store(
        store: Object<FungibleStore>
    ): address {
        let metadata = fungible_asset::store_metadata(store);
        object::object_address(&metadata)
    }

    public fun deposit(
        recipient_addr: address,
        fa: FungibleAsset
    ) {
        primary_fungible_store::deposit(recipient_addr, fa)
    }

    // ─────────────── Test Harness ───────────────
    /// Testing-only initializer for the FA module.
    #[test_only]
    public fun init_for_test() {
        init_module(&package_manager::get_resource_signer());
    }
}
