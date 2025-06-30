#[test_only]
module ciswap::test_assets {
    //! ============================================================
    //! Module: ciswap::test_fungible_assets
    //! ------------------------------------------------------------
    //! Unit-test helpers and regression tests for CiSwap’s
    //! fungible-asset utilities. This file:
    //!   - Bootstraps the package manager and FA utility modules
    //!   - Deploys mock tokens: CETUS, USDC, BUSD, BNB
    //!   - Provides helpers to mint AptosCoin and mock FA tokens
    //!   - Contains three concrete tests:
    //!       1. `test_mint_apt`       – mints native APT
    //!       2. `test_mint_fa_tokens` – mints the mock FA tokens
    //!       3. `test_mint_managed_coins`   – mints managed coins
    //! ============================================================

    // ───────────── Imports ─────────────
    use std::signer::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::managed_coin::{Self};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::primary_fungible_store::{Self};
    use aptos_framework::string::{Self};
    use ciswap::package_manager::{Self};
    use aptos_framework::fungible_asset::{Self};
    use ciswap::fa_utils::{Self};
    use ciswap::setup::{Self};
    use aptos_framework::object::{Self};

    // ───────────── Constants ─────────────
    const TESTS_ASSETS_ADMIN: address = @tests_assets_admin;
    const DEPLOYER: address = @deployer;

    const ERR_APT_BALANCE_MISMATCH: u64 = 101;
    const ERR_CETUS_BALANCE_MISMATCH: u64 = 201;
    const ERR_USDC_BALANCE_MISMATCH: u64 = 202;
    const ERR_BUSD_BALANCE_MISMATCH: u64 = 203;
    const ERR_BNB_BALANCE_MISMATCH: u64  = 204;
    const ERR_MANAGED_COIN_BALANCE_MISMATCH: u64 = 301;
    const ERR_WRAP_BALANCE_MISMATCH: u64 = 302;

    // ───────────── Test Support Structs ─────────────
    struct TestCoins has key, store {
        cetus_addr: address,
        usdc_addr:  address,
        busd_addr:  address,
        bnb_addr:   address,
    }

    struct Scallop has drop {}
    struct Suilend has drop {}

    // ───────────── Test Environment Setup ─────────────
    public fun setup_tests() {
        setup::setup(); // Initializes package manager and fa_utils
    }

    // ───────────── Deploy Mock Fungible Assets ─────────────
    public fun init_assets() {
        let resource_signer = package_manager::get_resource_signer();
        let fa_admin = account::create_signer_for_test(TESTS_ASSETS_ADMIN);

        let cetus_addr = fa_utils::create_fungible_asset(
            &resource_signer,
            b"CETUS",
            string::utf8(b"Cetus Protocol"),
            string::utf8(b"CETUS"),
            string::utf8(b"https://s2.coinmarketcap.com/static/img/coins/64x64/25114.png"),
            string::utf8(b"https://cetus.zone"),
        );

        let usdc_addr = fa_utils::create_fungible_asset(
            &resource_signer,
            b"USDC",
            string::utf8(b"USD Coin"),
            string::utf8(b"USDC"),
            string::utf8(b"https://s2.coinmarketcap.com/static/img/coins/64x64/3408.png"),
            string::utf8(b"https://www.circle.com/usdc"),
        );

        let busd_addr = fa_utils::create_fungible_asset(
            &resource_signer,
            b"BUSD",
            string::utf8(b"Binance USD"),
            string::utf8(b"BUSD"),
            string::utf8(b"https://s2.coinmarketcap.com/static/img/coins/64x64/4687.png"),
            string::utf8(b"https://www.binance.com/en/busd"),
        );

        let bnb_addr = fa_utils::create_fungible_asset(
            &resource_signer,
            b"BNB",
            string::utf8(b"Binance Coin"),
            string::utf8(b"BNB"),
            string::utf8(b"https://s2.coinmarketcap.com/static/img/coins/64x64/2710.png"),
            string::utf8(b"https://www.binance.com/en/bnb"),
        );

        // Also deploy two managed-coin types
        managed_coin::initialize<Scallop>(
            &resource_signer,
            b"Scallop",
            b"SCLP",
            8,
            false,
        );

        managed_coin::initialize<Suilend>(
            &resource_signer,
            b"Suilend",
            b"SEND",
            8,
            false,
        );

        move_to<TestCoins>(
            &fa_admin,
            TestCoins {
                cetus_addr,
                usdc_addr,
                busd_addr,
                bnb_addr,
            },
        );
    }

    // ───────────── Mint a Fungible Asset ─────────────
    public fun mint_to_address(
        fa_address: address,
        to: address,
        amount: u64,
    ) {
        let fa = fa_utils::mint(fa_address, amount);
        primary_fungible_store::deposit(to, fa)
    }

    // ───────────── Register & Mint Native APT ─────────────
    public fun register_and_mint_aptos_coin(
        aptos_framework: &signer,
        user: &signer,
        amount: u64,
    ) {
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test_without_aggregator_factory(aptos_framework);
        coin::register<AptosCoin>(user);
        aptos_coin::mint(aptos_framework, signer::address_of(user), amount);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // ───────────── Test 1: Mint AptosCoin ─────────────
    #[test(user = @0xc0ffee, aptos_framework = @aptos_framework)]
    public fun test_mint_apt(user: &signer, aptos_framework: &signer) {
        setup_tests();
        account::create_account_for_test(signer::address_of(user));
        register_and_mint_aptos_coin(aptos_framework, user, 5_000);
        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == 5_000, ERR_APT_BALANCE_MISMATCH);
    }

    // ───────────── Test 2: Mint Mock FA Tokens ─────────────
    #[test(user = @0xc0ffee)]
    public fun test_mint_fa_tokens(user: &signer) acquires TestCoins {
        setup_tests();
        init_assets();
        let test_coins = borrow_global<TestCoins>(TESTS_ASSETS_ADMIN);

        mint_to_address(test_coins.cetus_addr, signer::address_of(user), 100);
        mint_to_address(test_coins.usdc_addr,  signer::address_of(user), 200);
        mint_to_address(test_coins.busd_addr,  signer::address_of(user), 300);
        mint_to_address(test_coins.bnb_addr,   signer::address_of(user), 400);

        assert!(fa_utils::balance_of(signer::address_of(user), test_coins.cetus_addr) == 100, ERR_CETUS_BALANCE_MISMATCH);
        assert!(fa_utils::balance_of(signer::address_of(user), test_coins.usdc_addr) == 200, ERR_USDC_BALANCE_MISMATCH);
        assert!(fa_utils::balance_of(signer::address_of(user), test_coins.busd_addr) == 300, ERR_BUSD_BALANCE_MISMATCH);
        assert!(fa_utils::balance_of(signer::address_of(user), test_coins.bnb_addr) == 400, ERR_BNB_BALANCE_MISMATCH);
    
        // take some of the coins and burn them
        let cetus_fa = fa_utils::withdraw_fa_from_address(
            user,
            signer::address_of(user),
            test_coins.cetus_addr,
            50
        );
        // burn the fungible asset
        fa_utils::burn(cetus_fa);
        // check the balance after burning
        assert!(fa_utils::balance_of(signer::address_of(user), test_coins.cetus_addr) == 50, ERR_CETUS_BALANCE_MISMATCH);
    }

    // ───────────── Test 3: Mint Managed-Coin Tokens ─────────────
    #[test(user = @0xc0ffee)]
    public fun test_mint_mananged_coins(user: &signer) {
        setup_tests();
        init_assets();
        let resource_signer = package_manager::get_resource_signer();
        account::create_account_for_test(signer::address_of(user));

        managed_coin::register<Scallop>(user);
        managed_coin::mint<Scallop>(&resource_signer, signer::address_of(user), 1000);
        assert!(coin::balance<Scallop>(signer::address_of(user)) == 1000, ERR_MANAGED_COIN_BALANCE_MISMATCH);

        managed_coin::register<Suilend>(user);
        managed_coin::mint<Suilend>(&resource_signer, signer::address_of(user), 1000);
        assert!(coin::balance<Suilend>(signer::address_of(user)) == 1000, ERR_MANAGED_COIN_BALANCE_MISMATCH);
    }

    // ───────────── Test Wrap ─────────────
    #[test(user = @0xc0ffee)]
    public fun test_wrap(user: &signer) {
        setup_tests();
        init_assets();
        // Wrap Scallop into a fungible store
        account::create_account_for_test(signer::address_of(user));
        // Register Scallop managed coin and mint some
        let resource_signer = package_manager::get_resource_signer();
        managed_coin::register<Scallop>(user);
        // Mint 1000 Scallop coins to the user
        managed_coin::mint<Scallop>(&resource_signer, signer::address_of(user), 1000);
        // Withdraw 50 Scallop coins to wrap them into a fungible asset
        let coin = coin::withdraw<Scallop>(user, 50);
        let fa = fa_utils::wrap<Scallop>(coin);
        let fa_addr = object::object_address(&fungible_asset::metadata_from_asset(&fa));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        // Check balances
        assert!(
            fa_utils::balance_of(signer::address_of(user), 
            fa_addr
        ) == 50, ERR_WRAP_BALANCE_MISMATCH);
    }
}
