#[test_only]
module ciswap::tests_create_pair {
    use tests_coins::test_coins::{
        Self, 
        TestSTARCI, 
        TestBUSD, 
        TestUSDC, 
        TestBNB, 
    };
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::genesis::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::signer::{Self};
    use aptos_framework::math64::{Self};
    use ciswap::swap::{Self, LPToken, VirtualX };
    use ciswap::pool_math_utils::{Self};
    use aptos_framework::managed_coin::{Self};

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
    /// - `deployer`, `admin`, `treasury`, `resource_account`, `aptos_framework`: signers for various roles
    public fun setup_test_with_genesis(
        deployer: &signer, 
        admin: &signer, 
        treasury: &signer, 
        resource_account: &signer, 
        aptos_framework: &signer
    ) {
        // Run genesis setup for the test environment
        genesis::setup();
        // Call the helper to set up accounts and initialize the swap module
        setup_test(
            deployer, 
            admin, 
            treasury, 
            resource_account, 
            aptos_framework
        );
    }

    /// Sets up accounts and initializes the swap module
    ///
    /// # Arguments
    /// - `deployer`, `admin`, `treasury`, `resource_account`, `aptos_framework`: signers for various roles
    public fun setup_test(
        deployer: &signer, 
        admin: &signer, 
        treasury: &signer, 
        resource_account: &signer, 
        aptos_framework: &signer
    ) {
        // Create test accounts for deployer, admin, and treasury
        account::create_account_for_test(signer::address_of(deployer));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(treasury));
        // Create the resource account for the swap module
        resource_account::create_resource_account(
            deployer,
            b"ciswap", 
            b""
        );
        // Initialize the swap module and set the fee recipient
        swap::initialize(resource_account);
        swap::set_fee_to(admin, signer::address_of(treasury));
        // Set up coin conversion map for the framework
        coin::create_coin_conversion_map(aptos_framework);
    }

    /// Test: Create a new pair and check all balances and invariants
    ///
    /// # Arguments
    /// - `deployer`, `admin`, `resource_account`, `treasury`, `alice`, `aptos_framework`: signers for various roles
    #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
    fun test_create_pair(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        alice: &signer,
        aptos_framework: &signer,
    ) {
        // Create the test account for Alice
        account::create_account_for_test(signer::address_of(alice));
        // Setup the test environment (genesis, module, coins)
        setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
        // Initialize and mint test coins for Alice
        let coin_owner = test_coins::init_coins();
        test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
        // Mint AptosCoin for Alice (for pool creation fee)
        let aptos_balance: u64 = 100 * math64::pow(10, 8);
        test_coins::register_and_mint_aptos_coin(aptos_framework, alice, aptos_balance);
        // Create a pool address (unique for this test)
        let pool_addr = @0x23456;
        // Create a new pair (pool) with initial virtual liquidity
        swap::create_pair<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100 * math64::pow(10, 8),
            200 * math64::pow(10, 8)
        );
        // Check token A, B, and virtual balances in the pool
        let (
            token_a_balance, 
            token_b_balance, 
            virtual_token_a_balance, 
            virtual_token_b_balance
        ) = swap::token_balances<TestSTARCI, TestBUSD>(pool_addr);
        // Token A balance should be zero after creation
        assert!(
            token_a_balance == 0, 
            ERROR_TOKEN_A_NOT_ZERO
        );
        // Token B balance should be zero after creation
        assert!(
            token_b_balance == 0, 
            ERROR_TOKEN_B_NOT_ZERO
        );
        // Virtual token A balance should match initial value
        assert!(
            virtual_token_a_balance == 100 * math64::pow(10, 8), 
            ERROR_VIRTUAL_TOKEN_A_MISMATCH
        );
        // Virtual token B balance should match initial value
        assert!(
            virtual_token_b_balance == 200 * math64::pow(10, 8), 
            ERROR_VIRTUAL_TOKEN_B_MISMATCH
        );
        // Check locked LP token balance matches calculated locked liquidity
        let locked_lp_token_balance = swap::balance_locked_lp<TestSTARCI, TestBUSD>(pool_addr);
        assert!(
            locked_lp_token_balance == 
            pool_math_utils::calculate_locked_liquidity(
                virtual_token_a_balance, 
                virtual_token_b_balance
            )
        , 
        ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH);
        // Check Alice's AptosCoin balance (should be unchanged after pool creation)
        let current_aptos_balance = coin::balance<AptosCoin>(signer::address_of(alice));
        assert!(
            current_aptos_balance == aptos_balance - swap::get_creation_fee_in_apt(), 
            ERROR_APTOS_BALANCE_MISMATCH
        );
    }
}