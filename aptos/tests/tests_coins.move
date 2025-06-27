#[test_only]
module tests_coins::test_coins {
    use aptos_framework::account::{Self};
    use aptos_framework::managed_coin::{Self};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::math64::{Self};
    use std::signer::{Self};

    struct TestSTARCI {}
    struct TestBUSD {}
    struct TestUSDC {}
    struct TestBNB {}
    struct TestAPT {}

    public fun init_coins(): signer {
        let account = account::create_account_for_test(@tests_coins);
        // init coins
        managed_coin::initialize<TestSTARCI>(
            &account,
            b"STARCI",
            b"STARCI",
            9,
            false,
        );
        managed_coin::initialize<TestBUSD>(
            &account,
            b"Busd",
            b"BUSD",
            9,
            false,
        );

        managed_coin::initialize<TestUSDC>(
            &account,
            b"USDC",
            b"USDC",
            9,
            false,
        );

        managed_coin::initialize<TestBNB>(
            &account,
            b"BNB",
            b"BNB",
            9,
            false,
        );
        managed_coin::initialize<TestAPT>(
            &account,
            b"Aptos",
            b"APT",
            9,
            false,
        );

        account
    }


    public entry fun register_and_mint<CoinType>(account: &signer, to: &signer, amount: u64) {
      managed_coin::register<CoinType>(to);
      managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
    }

    public entry fun mint<CoinType>(account: &signer, to: &signer, amount: u64) {
        managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
    }
}