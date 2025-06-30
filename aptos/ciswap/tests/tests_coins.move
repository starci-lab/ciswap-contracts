// #[test_only]
// module tests_coins::test_coins {
//     use aptos_framework::account::{Self};
//     use aptos_framework::managed_coin::{Self};
//     use aptos_framework::aptos_coin::{Self, AptosCoin};
//     use aptos_framework::math64::{Self};
//     use aptos_framework::coin::{Self};
//     use std::signer::{Self};

//     /// Dummy coin types for testing
//     struct TestSTARCI {}
//     struct TestBUSD {}
//     struct TestUSDC {}
//     struct TestBNB {}

//     /// Initializes all test coins and returns the coin owner signer
//     public fun init_coins(): signer {
//         let account = account::create_account_for_test(@tests_coins);
//         // init coins
//         managed_coin::initialize<TestSTARCI>(
//             &account,
//             b"STARCI",
//             b"STARCI",
//             9,
//             false,
//         );
//         managed_coin::initialize<TestBUSD>(
//             &account,
//             b"Busd",
//             b"BUSD",
//             9,
//             false,
//         );
//         managed_coin::initialize<TestUSDC>(
//             &account,
//             b"USDC",
//             b"USDC",
//             9,
//             false,
//         );
//         managed_coin::initialize<TestBNB>(
//             &account,
//             b"BNB",
//             b"BNB",
//             9,
//             false,
//         );
//         account
//     }

//     /// Registers and mints a given amount of CoinType to the recipient
//     public fun register_and_mint<CoinType>(account: &signer, to: &signer, amount: u64) {
//       managed_coin::register<CoinType>(to);
//       managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
//     }

//     /// Mints a given amount of CoinType to the recipient (assumes already registered)
//     public fun mint<CoinType>(account: &signer, to: &signer, amount: u64) {
//         managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
//     }
// // 
//     /// Mint APT
//     public fun register_and_mint_aptos_coin(aptos_framework: &signer, user: &signer, amount: u64) {
//         let (burn_cap, apt_coin) = 
//             aptos_coin::initialize_for_test_without_aggregator_factory(aptos_framework);
//         coin::register<AptosCoin>(user);
//         aptos_coin::mint(aptos_framework, signer::address_of(user), amount);
//         coin::destroy_burn_cap(burn_cap);
//         coin::destroy_mint_cap(apt_coin);
//     }

//     /// Test: Register and mint all test coins for a user
//     #[test(user = @0xabcde)]
//     fun test_register_and_mint_all(user: &signer) {
//         let coin_owner = init_coins();
//         register_and_mint<TestSTARCI>(&coin_owner, user, 1000);
//         register_and_mint<TestBUSD>(&coin_owner, user, 1000);
//         register_and_mint<TestUSDC>(&coin_owner, user, 1000);
//         register_and_mint<TestBNB>(&coin_owner, user, 1000);
//         // Check balances are correct
//         assert!(coin::balance<TestSTARCI>(signer::address_of(user)) == 1000, 1);
//         assert!(coin::balance<TestBUSD>(signer::address_of(user)) == 1000, 2);
//         assert!(coin::balance<TestUSDC>(signer::address_of(user)) == 1000, 3);
//         assert!(coin::balance<TestBNB>(signer::address_of(user)) == 1000, 4);
//     }
// }