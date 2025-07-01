#[test_only]
module ciswap::tests_create_pair {
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::genesis::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::signer::{Self};
    use aptos_framework::math64::{Self};
    use ciswap::swap::{Self };
    use ciswap::pool_math_utils::{Self};
    use aptos_framework::managed_coin::{Self};
    use ciswap::setup::{Self};
    use ciswap::tests_assets::{ Self, TestFAs };

    // Error codes for test assertions
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 0;
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 1;
    const ERROR_VIRTUAL_TOKEN_A_MISMATCH: u64 = 2;
    const ERROR_VIRTUAL_TOKEN_B_MISMATCH: u64 = 3;
    const ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH: u64 = 4;
    const ERROR_APTOS_BALANCE_MISMATCH: u64 = 5;

    /// Sets up the test environment with genesis and all required accounts/resources
    ///
    /// # Arguments
    /// - deployer, admin, treasury, resource_account, aptos_framework: signers for various roles
    public fun setup_tests() {
        setup::setup(); // Initializes package manager and fa_utils
        tests_assets::setup(); // Initializes test assets
        swap::init_for_test(); // Initializes the swap module
    }


    /// Test: Create a new pair and check all balances and invariants
    ///
    /// # Arguments
    /// - deployer, admin, resource_account, treasury, alice, aptos_framework: signers for various roles
    #[test(
        deployer = @deployer, 
        admin = @default_admin, 
        resource_account = @ciswap, 
        alice = @0x12346
    )]
    fun test_create_pair(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        alice: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        tests_assets::register_and_mint_aptos_coin(
            alice, 
            100_000_000 // Mint 1 APT
        );
        // Create the test account for Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        // Alice call the create_pair function
        swap::create_pair(
            alice,
            cetus_addr,
            usdc_addr,
            200_000_000, // 1 CETUS
            100_000_000, // 1 USDC
        );
        // Check your APT balance, if go correct, you will have 0.9 APT left
        assert!(
            coin::balance<AptosCoin>(signer::address_of(alice)) == 90_000_000,
            ERROR_APTOS_BALANCE_MISMATCH
        );
        // Check the liquidity pool balances
        let (
            cetus_balance,
            usdc_balance,
            debt_cetus_balance,
            debt_usdc_balance,
         ) = swap::token_balances(0);
        assert!(cetus_balance == 0, ERROR_TOKEN_A_NOT_ZERO);
        assert!(usdc_balance == 0, ERROR_TOKEN_B_NOT_ZERO);
        assert!(debt_cetus_balance == 200_000_000, ERROR_TOKEN_A_NOT_ZERO);
        assert!(debt_usdc_balance == 100_000_000, ERROR_TOKEN_B_NOT_ZERO);
        // check k last
        let k_sqrt_last = swap::k_sqrt_last(0);
        assert!(k_sqrt_last == math64::sqrt(200_000_000 * 100_000_000), 
            1
        );
    }

    #[test(
        deployer = @deployer, 
        admin = @default_admin, 
        resource_account = @ciswap, 
        alice = @0x12346
    )]
    fun test_create_10_pairs(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        alice: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        tests_assets::register_and_mint_aptos_coin(
            alice, 
            100_000_000 // Mint 1 APT
        );
        let balance_lelf = 100_000_000; // 1 APT
        // Create 10 pairs
        for (i in 0..9) {
            let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
            swap::create_pair(
                alice,
                cetus_addr,
                usdc_addr,
                200_000_000 + i * 10_000_000, // 1 CETUS + i * 10M
                100_000_000 + i * 5_000_000, // 1 USDC + i * 5M
            );
            balance_lelf = balance_lelf - 10_000_000;
            assert!(
                coin::balance<AptosCoin>(signer::address_of(alice)) == balance_lelf,
                ERROR_APTOS_BALANCE_MISMATCH
            );
        };
        // Check your APT balance, if go correct, you will have no APT left
    }
}