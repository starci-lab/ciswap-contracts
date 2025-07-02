#[test_only]
module ciswap::tests_add_liquidity {
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
    use ciswap::tests_create_pair::{Self};
    use ciswap::position::{Self};

    // Error codes for test assertions
    const ERR_DESIRED_X_NOT_MISMATCH: u64 = 0;
    const ERR_DESIRED_Y_NOT_MISMATCH: u64 = 1;
    const ERR_K_LAST_MISMATCH: u64 = 2;

    /// Sets up the test environment with genesis and all required accounts/resources
    ///
    /// # Arguments
    /// - deployer, admin, treasury, resource_account, aptos_framework: signers for various roles
    public fun setup_tests() {
        setup::setup(); // Initializes package manager and fa_utils
        tests_assets::setup(); // Initializes test assets
        position::init_for_test(); // Initializes the position module
        swap::init_for_test(); // Initializes the swap module
    }

    public fun add_liquidity_for_test(
        user: &signer,
        cetus_amount: u64, // 2 CETUS
        usdc_amount: u64 // 1 USDC
    ) {
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        tests_assets::mint_to_address(
            cetus_addr,
            signer::address_of(user),
            200_000_000, // Mint 2 CETUS
        );
        tests_assets::mint_to_address(
            usdc_addr,
            signer::address_of(user),
            100_000_000, // Mint 1 USDC
        );
        // Alice call the create_pair function
        swap::add_liquidity(
            user,
            0, // Pool ID
            200_000_000, // Amount of token A (e.g., 2 CETUS)
            100_000_000, // Amount of token B (e.g., 1 USDC)
        );
    }

    /// Test: Create a new pair and check all balances and invariants
    /// # Arguments
    /// - deployer, admin, resource_account, treasury, alice, aptos_framework: signers for various roles
    #[test(
        alice = @0x12346
    )]
    fun test_add_liquidity(
        alice: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        tests_create_pair::create_pair_for_test(
            alice,
            200_000_000, // 2 CETUS
            100_000_000  // 1 USDC
        ); // Initializes the add liquidity module
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        tests_assets::mint_to_address(
            cetus_addr,
            signer::address_of(alice),
            200_000_000, // Mint 2 CETUS
        );
        tests_assets::mint_to_address(
            usdc_addr,
            signer::address_of(alice),
            100_000_000, // Mint 2 USDC
        );
        let (desired_x, desired_y) = swap::add_liquidity(
            alice,
            0, // Pool ID
            100_000_000, // Amount of token A (e.g., 1 CETUS)
            100_000_000, // Amount of token B (e.g., 1 USDC)
        );
        assert!(desired_x == 100_000_000, ERR_DESIRED_X_NOT_MISMATCH);
        assert!(desired_y == 50_000_000, ERR_DESIRED_Y_NOT_MISMATCH); 

        let k_sqrt_last = swap::k_sqrt_last(0);
        assert!(
            k_sqrt_last == math64::sqrt(
                (200_000_000 + 100_000_000) * (100_000_000 + 50_000_000)
            ), 
            ERR_K_LAST_MISMATCH
        ); // Check k_sqrt_last is updated correctly

        let (desired_x, desired_y) = swap::add_liquidity(
            alice,
            0, // Pool ID
            100_000_000, // Amount of token A (e.g., 1 CETUS)
            100_000_000, // Amount of token B (e.g., 1 USDC)
        );
        assert!(desired_x == 100_000_000, ERR_DESIRED_X_NOT_MISMATCH);
        assert!(desired_y == 50_000_000, ERR_DESIRED_Y_NOT_MISMATCH);
        let k_sqrt_last = swap::k_sqrt_last(0);
        assert!(
            k_sqrt_last == math64::sqrt(
                (200_000_000 + 200_000_000) * (100_000_000 + 100_000_000)
            ), 
            ERR_K_LAST_MISMATCH
        ); // Check k_sqrt_last is updated correctly
    }
}