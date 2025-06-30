// #[test_only]
// module ciswap::tests_swap {
//     use aptos_framework::genesis::{Self};
//     use aptos_framework::account::{Self};
//     use aptos_framework::resource_account::{Self};
//     use aptos_framework::coin::{Self};
//     use aptos_framework::signer::{Self};
//     use aptos_framework::math64::{Self};
//     use ciswap::swap::{Self, LPToken, VirtualX };
//     use ciswap::pool_math_utils::{Self};
//     use aptos_framework::aptos_coin::{Self, AptosCoin};
//     use tests_coins::test_coins::{
//         Self, 
//         TestSTARCI, 
//         TestBUSD, 
//         TestUSDC, 
//         TestBNB, 
//     };

//     // Error codes for test assertions
//     const ERROR_TOKEN_A_NOT_ZERO: u64 = 0;
//     const ERROR_TOKEN_B_NOT_ZERO: u64 = 1;
//     const ERROR_VIRTUAL_TOKEN_A_MISMATCH: u64 = 2;
//     const ERROR_VIRTUAL_TOKEN_B_MISMATCH: u64 = 3;
//     const ERROR_LOCKED_LP_TOKEN_BALANCE_MISMATCH: u64 = 4;
//     const ERROR_SHOULD_FAIL: u64 = 100;

//     /// Sets up the test environment with genesis and all required accounts/resources
//     public fun setup_test_with_genesis(
//         deployer: &signer, 
//         admin: &signer, 
//         treasury: &signer, 
//         resource_account: &signer, 
//         aptos_framework: &signer
//     ) {
//         genesis::setup();
//         setup_test(
//             deployer, 
//             admin, 
//             treasury, 
//             resource_account, 
//             aptos_framework
//         );
//     }

//     /// Sets up accounts and initializes the swap module
//     public fun setup_test(
//         deployer: &signer, 
//         admin: &signer, 
//         treasury: &signer, 
//         resource_account: &signer, 
//         aptos_framework: &signer
//     ) {
//         account::create_account_for_test(signer::address_of(deployer));
//         account::create_account_for_test(signer::address_of(admin));
//         account::create_account_for_test(signer::address_of(treasury));
//         resource_account::create_resource_account(
//             deployer,
//             b"ciswap", 
//             b""
//         );
//         swap::initialize(resource_account);
//         swap::set_fee_to(admin, signer::address_of(treasury));
//         coin::create_coin_conversion_map(aptos_framework);
//     }

//     /// Test: Basic swap and check balances after the swap
//     #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
//     fun test_swap(
//         deployer: &signer,
//         admin: &signer,
//         resource_account: &signer,
//         treasury: &signer,
//         alice: &signer,
//         aptos_framework: &signer,
//     ) {
//         let pool_addr = @0x23456;
//         account::create_account_for_test(signer::address_of(alice));
//         // Setup the test environment
//         setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
//         // Initialize coins
//         let coin_owner = test_coins::init_coins();
//         test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         // Mint AptosCoin for Alice (for pool creation fee)
//         let aptos_balance: u64 = 100 * math64::pow(10, 8);
//         test_coins::register_and_mint_aptos_coin(aptos_framework, alice, aptos_balance);
//         // Create a pair
//         swap::create_pair<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             100 * math64::pow(10, 8),
//             200 * math64::pow(10, 8)
//         );
//         coin::register<VirtualX<TestSTARCI, TestBUSD>>(alice);
//         coin::register<VirtualX<TestBUSD, TestSTARCI>>(alice);
//         // add liquidity
//         swap::add_liquidity<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             100,
//             200
//         );
//         // swap
//         let amount_in = 10 * math64::pow(10, 8);
//         let alice_address = signer::address_of(alice);
//         let (amount_out, amount_virtual_out) = swap::swap<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             amount_in,
//             true,
//             alice_address, // recipient is the same as the sender
//             0 // 0 means no slippage,
//         );
//         // check balance
//         let alice_starci_balance = coin::balance<TestSTARCI>(signer::address_of(alice));
//         let alice_busd_balance = coin::balance<TestBUSD>(signer::address_of(alice));
//         let virtual_balance = coin::balance<VirtualX<TestBUSD, TestSTARCI>>(signer::address_of(alice));
//         // check the balances
//         assert!(alice_starci_balance == 100 * math64::pow(10, 8) - 100 - amount_in, 0);
//         assert!(alice_busd_balance == 100 * math64::pow(10, 8) - 200 + amount_out, 0);
//         assert!(virtual_balance == amount_virtual_out, 0);
//     }

//     /// Test: Swap with slippage protection (should fail if output is too low)
//     #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
//     fun test_swap_with_slippage_should_fail(
//         deployer: &signer,
//         admin: &signer,
//         resource_account: &signer,
//         treasury: &signer,
//         alice: &signer,
//         aptos_framework: &signer,
//     ) {
//         let pool_addr = @0x23456;
//         account::create_account_for_test(signer::address_of(alice));
//         setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
//         let coin_owner = test_coins::init_coins();
//         test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         //mint AptosCoin for Alice (for pool creation fee)
//         let aptos_balance: u64 = 100 * math64::pow(10, 8);
//         test_coins::register_and_mint_aptos_coin(aptos_framework, alice, aptos_balance);
//         swap::create_pair<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             100 * math64::pow(10, 8),
//             200 * math64::pow(10, 8)
//         );
//         swap::add_liquidity<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             100,
//             200
//         );
//         let amount_in = 10 * math64::pow(10, 8);
//         let alice_address = signer::address_of(alice);
//         // Set a very low limit_amount_calculated to force slippage failure
//         swap::swap<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             amount_in,
//             true,
//             alice_address,
//             1 // limit is too low, should fail
//         );
//     }

//     /// Test: Swap with insufficient liquidity (should fail)
//     #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
//     #[expected_failure]
//     fun test_swap_insufficient_liquidity_should_fail(
//         deployer: &signer,
//         admin: &signer,
//         resource_account: &signer,
//         treasury: &signer,
//         alice: &signer,
//         aptos_framework: &signer,
//     ) {
//         let pool_addr = @0x23456;
//         account::create_account_for_test(signer::address_of(alice));
//         setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
//         let coin_owner = test_coins::init_coins();
//         test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         swap::create_pair<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             100 * math64::pow(10, 8),
//             200 * math64::pow(10, 8)
//         );
//         // No liquidity added
//         let amount_in = 10 * math64::pow(10, 8);
//         let alice_address = signer::address_of(alice);
//         swap::swap<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             amount_in,
//             true,
//             alice_address,
//             0
//         );
//     }

//     /// Test: Swap on a non-existent pool (should fail)
//     #[test(deployer = @deployer, admin = @default_admin, resource_account = @ciswap, treasury = @0x23456, alice = @0x12346, aptos_framework = @0x1)]
//     #[expected_failure]
//     fun test_swap_non_existent_pool_should_fail(
//         deployer: &signer,
//         admin: &signer,
//         resource_account: &signer,
//         treasury: &signer,
//         alice: &signer,
//         aptos_framework: &signer,
//     ) {
//         let pool_addr = @0x99999;
//         account::create_account_for_test(signer::address_of(alice));
//         setup_test_with_genesis(deployer, admin, treasury, resource_account, aptos_framework);
//         let coin_owner = test_coins::init_coins();
//         test_coins::register_and_mint<TestSTARCI>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * math64::pow(10, 8));
//         // No pool created at pool_addr
//         let amount_in = 10 * math64::pow(10, 8);
//         let alice_address = signer::address_of(alice);
//         swap::swap<TestSTARCI, TestBUSD>(
//             alice,
//             pool_addr,
//             amount_in,
//             true,
//             alice_address,
//             0
//         );
//         // If we reach here, the test should fail
//         assert!(false, ERROR_SHOULD_FAIL);
//     }
// }