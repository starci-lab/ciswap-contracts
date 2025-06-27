#[test_only]
module ciswap::tests_add_liquidity {
    use tests_coins::test_coins::{
        Self, 
        TestSTARCI, 
        TestBUSD, 
        TestUSDC, 
        TestBNB, 
    };
    use aptos_framework::genesis::{Self};
    use aptos_framework::account::{Self};
    use aptos_framework::resource_account::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::signer::{Self};
    use aptos_framework::math64::{Self};
    use ciswap::swap::{Self, LPToken, VirtualX };
    use ciswap::pool_math_utils::{Self};
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    // Error codes for test assertions
    const ERROR_TOKEN_A_NOT_ZERO: u64 = 0;
    const ERROR_TOKEN_B_NOT_ZERO: u64 = 1;
    const ERROR_VIRTUAL_TOKEN_A_MISMATCH: u64 = 2;
    const ERROR_VIRTUAL_TOKEN_B_MISMATCH: u64 = 3;
    const ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH: u64 = 4;
    const ERROR_SHOULD_FAIL: u64 = 100;

    /// Sets up the test environment with genesis and all required accounts/resources
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

    /// Sets up accounts and initializes the swap module
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

    /// Test: Add liquidity to a pool and check LP token and fee accounting
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
        test_coins::register_and_mint_aptos_coin(aptos_framework, alice, 100 * math64::pow(10, 8));
        // Create a pool address
        let pool_addr = @0x23456;
        // Create a pair
        swap::create_pair<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100 * math64::pow(10, 8),
            200 * math64::pow(10, 8)
        );

        // Check the initial balances
        let k_last = swap::k_sqrt<TestSTARCI, TestBUSD>(pool_addr);

        // add liquidity
        swap::add_liquidity<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100,
            200
        );
        let k_last_after = swap::k_sqrt<TestSTARCI, TestBUSD>(pool_addr);
        // check your LP token balance
        let lp_token_balance = coin::balance<LPToken<TestSTARCI, TestBUSD>>(signer::address_of(alice));
        // get the fee amount
        // lp balance equal the differ in k
        assert!(lp_token_balance + swap::fee_amount<TestSTARCI, TestBUSD>(pool_addr) == (
            k_last_after - k_last
        ), ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH);
    }

    /// Test: Adding zero liquidity should fail
    #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
    fun test_add_zero_liquidity_should_fail(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        alice: &signer,
        aptos_framework: &signer,
    ) {
        account::create_account_for_test(signer::address_of(alice));
        setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
        let coin_owner = test_coins::init_coins();
        test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
        let pool_addr = @0x23456;
        swap::create_pair<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100 * math64::pow(10, 8),
            200 * math64::pow(10, 8)
        );
        // Should fail: adding zero liquidity
        swap::add_liquidity<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            0,
            0
        );
        // If we reach here, the test should fail
        assert!(false, ERROR_SHOULD_FAIL);
    }

    /// Test: Multiple users add liquidity to the same pool
    #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, bob = @0x12347, aptos_framework = @0x1)]
    fun test_multi_user_add_liquidity(
        deployer: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        alice: &signer,
        bob: &signer,
        aptos_framework: &signer,
    ) {
        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
        let coin_owner = test_coins::init_coins();
        test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestSTARCI>(&coin_owner, bob, 100 * math64::pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * math64::pow(10, 8));
        let pool_addr = @0x23456;
        swap::create_pair<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100 * math64::pow(10, 8),
            200 * math64::pow(10, 8)
        );
        // Alice adds liquidity
        swap::add_liquidity<TestSTARCI, TestBUSD>(
            alice,
            pool_addr,
            100,
            200
        );
        // Bob adds liquidity
        swap::add_liquidity<TestSTARCI, TestBUSD>(
            bob,
            pool_addr,
            50,
            100
        );
        // Check both LP balances are > 0
        let alice_lp = coin::balance<LPToken<TestSTARCI, TestBUSD>>(signer::address_of(alice));
        let bob_lp = coin::balance<LPToken<TestSTARCI, TestBUSD>>(signer::address_of(bob));
        assert!(alice_lp > 0, ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH);
        assert!(bob_lp > 0, ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH);
    }
}