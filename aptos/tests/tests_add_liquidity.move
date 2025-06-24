#[test_only]
module ciswap::tests_add_liquidity {
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
    use ciswap::pool_math_utils::{Self};

    // Import the swap module
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 0;
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 1;
    const ERROR_VIRTUAL_TOKEN_A_MISMATCH: u64 = 2;
    const ERROR_VIRTUAL_TOKEN_B_MISMATCH: u64 = 3;
    const ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH: u64 = 4;

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
    fun test_add_liqudity(
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

        // Check the initial balances
        let k_last = swap::k_sqrt<TestSTARCI, TestBUSD>();

        // add liquidity
        swap::add_liquidity<TestSTARCI, TestBUSD>(
            alice,
            100,
            200
        );
        let k_last_after = swap::k_sqrt<TestSTARCI, TestBUSD>();
        // check your LP token balance
        let lp_token_balance = coin::balance<LPToken<TestSTARCI, TestBUSD>>(signer::address_of(alice));
        // get the fee amount
        // lp balance equal the differ in k
        assert!(lp_token_balance + swap::fee_amount<TestSTARCI, TestBUSD>() == (
            k_last_after - k_last
        ), ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH);
    }
}