#[test_only]
module tests_create_pair::tests_create_pair {
    use tests_coins::test_coins::{
        Self, 
        TestSTARCI, 
        TestBUSD, 
        TestUSDC, 
        TestBNB, 
        TestAPT
    };
    use aptos_framework::genesis::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::signer::{Self};
    use aptos_framework::math64::{Self};
    use ciswap::swap::{Self, LPToken, VirtualX };

    // Import the swap module
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 0;
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 1;
    const ERROR_VIRTUAL_TOKEN_A_MISMATCH: u64 = 2;
    const ERROR_VIRTUAL_TOKEN_B_MISMATCH: u64 = 3;

    public fun setup_test_with_genesis(
        deployer: &signer, 
        admin: &signer, 
        treasury: &signer, 
        resource_account: &signer, 
        aptos_framework: &signer
    ) {
        genesis::setup();
        setup_test(
            deployer, 
            admin, 
            treasury, 
            resource_account, 
            aptos_framework
        );
    }

    public fun setup_test(
        deployer: &signer, 
        admin: &signer, 
        treasury: &signer, 
        resource_account: &signer, 
        aptos_framework: &signer
    ) {
        account::create_account_for_test(signer::address_of(deployer));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(treasury));
        resource_account::create_resource_account(
            deployer,
            b"ciswap", 
            b""
        );
        swap::initialize(resource_account);
        swap::set_fee_to(admin, signer::address_of(treasury));
        coin::create_coin_conversion_map(aptos_framework);
    }

    #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
    fun test_create_pair(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        alice: &signer,
        aptos_framework: &signer,
    ) {
        account::create_account_for_test(signer::address_of(alice));
        // Setup the test environment
        setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
        // Initialize coins
        let coin_owner = test_coins::init_coins();
        test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));

        // Create a pair
        swap::create_pair<TestSTARCI, TestBUSD>(
            alice,
            100 * math64::pow(10, 8),
            200 * math64::pow(10, 8)
        );
        // Check token A balance
        let (
            token_a_balance, 
            token_b_balance, 
            virtual_token_a_balance, 
            virtual_token_b_balance
        ) = swap::token_balances<TestSTARCI, TestBUSD>();
        assert!(
            token_a_balance == 0, 
            ERROR_TOKEN_A_NOT_ZERO
        );
        // Check token B balance
        assert!(
            token_b_balance == 0, 
            ERROR_TOKEN_B_NOT_ZERO
        );
        // Check virtual token A balance
        assert!(
            virtual_token_a_balance == 100 * math64::pow(10, 8), 
            ERROR_VIRTUAL_TOKEN_A_MISMATCH
        );
        // Check virtual token B balance
        assert!(
            virtual_token_b_balance == 200 * math64::pow(10, 8), 
            ERROR_VIRTUAL_TOKEN_B_MISMATCH
        );
    }
}