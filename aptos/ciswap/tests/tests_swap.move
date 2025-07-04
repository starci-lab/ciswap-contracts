#[test_only]
module ciswap::tests_swap {
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
    use ciswap::quoter::{Self};
    use ciswap::tests_add_liquidity::{Self};
    use ciswap::fa_utils::{Self};
    use aptos_std::debug::{Self};
    use aptos_framework::string::{Self};
    use ciswap::u64_utils::{Self};
    use aptos_framework::math128::{Self};

    // Error codes for test assertions
    const ERR_BALANCE_X_MISMATCH: u64 = 0;
    const ERR_BALANCE_Y_MISMATCH: u64 = 1;
    const ERR_FEE_X_MISMATCH: u64 = 2;
    const ERR_FEE_Y_MISMATCH: u64 = 3;
    const ERR_K_LAST_MISMATCH: u64 = 4;
    const ERR_FEE_DEBT_X_MISMATCH: u64 = 5;
    const ERR_FEE_DEBT_Y_MISMATCH: u64 = 6;

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

    /// Test: Create a new pair and check all balances and invariants
    /// # Arguments
    /// - deployer, admin, resource_account, treasury, alice, aptos_framework: signers for various roles
    #[test(
        alice = @0x12346,
        bob = @0x12347,
    )]
    fun test_swap_cetus_for_usdc(
        alice: &signer,
        bob: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        tests_create_pair::create_pair_for_test(
            alice,
            200_000_000, // 2 CETUS
            100_000_000  // 1 USDC
        ); // Initializes the add liquidity module
        let lp_nft_addr = tests_add_liquidity::add_liquidity_for_test(
            alice,
            100_000_000, // 1 CETUS
            50_000_000   // 0.5 USDC
        ); // Initializes the add liquidity module
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        
        tests_assets::mint_to_address(
            cetus_addr,
            signer::address_of(alice),
            200_000_000, // Mint 2 CETUS
        );
        // Quote first to check the swap price
        let (amount_out, amount_deb) = quoter::get_amount_out(
            0, // Pool ID
            10_000_000, // Amount of token CETUS to swap (0.1 CETUS)
            true, // Swap from CETUS to USDC
        );
        // Alice should have 2 CETUS now
        swap::swap(
            alice, // Sender is Alice
            0, // Pool ID
            10_000_000, // Amount of token CETUS to swap (0.1 CETUS)
            true,
            signer::address_of(bob), // Recipient is Alice
            0, // Minimum amount of token USDC to receive (0 USDC)
            0, // Minimum amount of token ciUSDC to receive (0 ciUSDC)
        );

        // We check balance of alice after the swap
        let alice_cetus_balance = fa_utils::balance_of(
            signer::address_of(alice),
            cetus_addr
        );
        assert!(
            alice_cetus_balance == 190_000_000, // Alice should have 1.9 CETUS left
            ERR_BALANCE_X_MISMATCH
        );
        let bob_usdc_balance = fa_utils::balance_of(
            signer::address_of(bob),
            usdc_addr
        );
        // pool has 4 cetus and 2 usdc
        // so that we will compute the swap price as follows:
        // 4 x 2 = (4 + 0. 1) * (2 - x)
        let raw = (
            200_000_000 
            - (
                (
                    math128::ceil_div(400_000_000u128 * 200_000_000u128, 400_000_000u128 + 10_000_000u128) as u64
                )
            )
        );
        let fee = 
            (raw * 3_000) / 1_000_000; // 0.3 USDC fee (0.1 CETUS * 0.003)
        let left = raw - fee; // 0.7 USDC left after fee
        debug::print(&bob_usdc_balance);
        assert!(
            bob_usdc_balance == 
            left, // Bob should have 0.3 USDC left after the swap
            ERR_BALANCE_Y_MISMATCH
        );
        // If the token distributed is correct, we now check fee distribution
        let (
            fee_x, 
            fee_y, 
            debt_fee_x, 
            debt_fee_y,
            protocol_fee_x,
            protocol_fee_y,
            protocol_fee_debt_x,
            protocol_fee_debt_y
        ) = swap::get_fees(0); // Get the fees for pool ID 0
        
        // Check the fees collected
        debug::print(&fee_x);
        debug::print(&fee_y);
        debug::print(&debt_fee_x);
        debug::print(&debt_fee_y);
        debug::print(&protocol_fee_x);
        debug::print(&protocol_fee_y);
        debug::print(&protocol_fee_debt_x);
        debug::print(&protocol_fee_debt_y);
        
        // Check the fee amounts
        debug::print(&fee);
        let protocol_fee = (fee * 100_000) / 1_000_000; // 10% of the fee goes to LPs
        let lp_fee = fee - protocol_fee; // 90% goes to protocol
        debug::print(&protocol_fee);
        debug::print(&lp_fee);

        // Assert the fees are correct
        assert!(fee_y == lp_fee, ERR_FEE_Y_MISMATCH); // No fees collected yet
        assert!(protocol_fee_y == protocol_fee, ERR_FEE_DEBT_Y_MISMATCH); // No fees collected yet
    }   

     /// Test: Create a new pair and check all balances and invariants
    /// # Arguments
    /// - deployer, admin, resource_account, treasury, alice, aptos_framework: signers for various roles
    #[test(
        alice = @0x12346,
        bob = @0x12347,
    )]
    fun test_swap_usdt_to_cetus(
        alice: &signer,
        bob: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        tests_create_pair::create_pair_for_test(
            alice,
            200_000_000, // 2 CETUS
            100_000_000  // 1 USDC
        ); // Initializes the add liquidity module
        tests_add_liquidity::add_liquidity_for_test(
            alice,
            100_000_000, // 1 CETUS
            50_000_000   // 0.5 USDC
        ); // Initializes the add liquidity module
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        
        tests_assets::mint_to_address(
            usdc_addr,
            signer::address_of(alice),
            200_000_000, // Mint 2 USDC
        );
        // Alice should have 2 CETUS now
        swap::swap(
            alice, // Sender is Alice
            0, // Pool ID
            10_000_000, // Amount of token A to swap (0.1 USDC)
            false,
            signer::address_of(bob), // Recipient is Alice
            0, // Minimum amount of token CETUS to receive (0 CETUS)
            0, // Minimum amount of token ciCETUS to receive (0 ciCETUS)
        );

        // We check balance of alice after the swap
        let alice_usdc_balance = fa_utils::balance_of(
            signer::address_of(alice),
            usdc_addr
        );
        assert!(
            alice_usdc_balance == 190_000_000, // Alice should have 1.9 CETUS left
            ERR_BALANCE_Y_MISMATCH
        );
        let bob_cetus_balance = fa_utils::balance_of(
            signer::address_of(bob),
            cetus_addr
        );
        // pool has 4 cetus and 2 usdc
        // so that we will compute the swap price as follows:
        // 4 x 2 = (4 + 0. 1) * (2 - x)
        let raw = (
            400_000_000 
            - (
                (
                    math128::ceil_div(400_000_000u128 * 200_000_000u128, 200_000_000u128 + 10_000_000u128) as u64
                )
            )
        );
        let fee = 
            (raw * 3_000) / 1_000_000; // 0.3 USDC fee (0.1 CETUS * 0.003)
        let left = raw - fee; // 0.7 USDC left after fee
        debug::print(&bob_cetus_balance);
        assert!(
            bob_cetus_balance == 
            left, // Bob should have 0.3 USDC left after the swap
            ERR_BALANCE_X_MISMATCH
        );
        // If the token distributed is correct, we now check fee distribution
        let (
            fee_x, 
            fee_y, 
            debt_fee_x, 
            debt_fee_y,
            protocol_fee_x,
            protocol_fee_y,
            protocol_fee_debt_x,
            protocol_fee_debt_y
        ) = swap::get_fees(0); // Get the fees for pool ID 0
        
        // Check the fees collected
        debug::print(&fee_x);
        debug::print(&fee_y);
        debug::print(&debt_fee_x);
        debug::print(&debt_fee_y);
        debug::print(&protocol_fee_x);
        debug::print(&protocol_fee_y);
        debug::print(&protocol_fee_debt_x);
        debug::print(&protocol_fee_debt_y);
        
        // Check the fee amounts
        debug::print(&fee);
        let protocol_fee = (fee * 100_000) / 1_000_000; // 10% of the fee goes to LPs
        let lp_fee = fee - protocol_fee; // 90% goes to protocol
        debug::print(&protocol_fee);
        debug::print(&lp_fee);

        // Assert the fees are correct
        assert!(fee_x == lp_fee, ERR_FEE_Y_MISMATCH); // No fees collected yet
        assert!(protocol_fee_x == protocol_fee, ERR_FEE_DEBT_Y_MISMATCH); // No fees collected yet
    }

    /// Test: Create a new pair and check all balances and invariants
    /// # Arguments
    /// - deployer, admin, resource_account, treasury, alice, aptos_framework: signers for various roles
    #[test(
        alice = @0x12346,
        bob = @0x12347,
    )]
    fun test_swap_cetus_for_usdc_and_debt_usdc(
        alice: &signer,
        bob: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        tests_create_pair::create_pair_for_test(
            alice,
            200_000_000, // 2 CETUS
            100_000_000  // 1 USDC
        ); // Initializes the add liquidity module
        tests_add_liquidity::add_liquidity_for_test(
            alice,
            100_000_000, // 1 CETUS
            50_000_000   // 0.5 USDC
        ); // Initializes the add liquidity module
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        
        tests_assets::mint_to_address(
            cetus_addr,
            signer::address_of(alice),
            1_000_000_000, // Mint 10 CETUS
        );
        // Alice should have 10 CETUS now
        swap::swap(
            alice, // Sender is Alice
            0, // Pool ID
            1_000_000_000, // Amount of token CETUS to swap (0.1 CETUS)
            true,
            signer::address_of(bob), // Recipient is Alice
            0, // Minimum amount of token USDC to receive (0 USDC)
            0, // Minimum amount of token ciUSDC to receive (0 ciUSDC)
        );

        // We check balance of alice after the swap
        let alice_cetus_balance = fa_utils::balance_of(
            signer::address_of(alice),
            cetus_addr
        );
        assert!(
            alice_cetus_balance == 0, // Alice should have 1.9 CETUS left
            ERR_BALANCE_X_MISMATCH
        );
        let bob_usdc_balance = fa_utils::balance_of(
            signer::address_of(bob),
            usdc_addr
        );
        let bob_debt_usdc_balance = fa_utils::balance_of(
            signer::address_of(bob),
            swap::get_address_debt_y(0)
        );
        debug::print(&bob_usdc_balance);
        debug::print(&bob_debt_usdc_balance);
        let (
            fee_x, 
            fee_y, 
            debt_fee_x, 
            debt_fee_y,
            protocol_fee_x,
            protocol_fee_y,
            protocol_fee_debt_x,
            protocol_fee_debt_y
        ) = swap::get_fees(0); // Get the fees for pool ID 0
        debug::print(&protocol_fee_y);
        //debug::print(&protocol_fee_debt_x);
        debug::print(&protocol_fee_debt_y);
        
        // Check the fee amounts
        // debug::print(&fee);
        // let protocol_fee = (fee * 100_000) / 1_000_000; // 10% of the fee goes to LPs
        // let lp_fee = fee - protocol_fee; // 90% goes to protocol
        // debug::print(&protocol_fee);
        // debug::print(&lp_fee);

        // // Assert the fees are correct
        // assert!(fee_y == lp_fee, ERR_FEE_Y_MISMATCH); // No fees collected yet
        // assert!(protocol_fee_y == protocol_fee, ERR_FEE_DEBT_Y_MISMATCH); // No fees collected yet
    }

    /// Test: Swap 10 times from CETUS to USDC and check the get_product_reserves_sqrt and get_product_balances_sqrt
    #[test(
        alice = @0x12346,
        bob = @0x12347,
    )]
    fun test_swap_cetus_for_usdc_10_times(
        alice: &signer,
        bob: &signer
    ) {
        setup_tests(); // Setup the test environment
        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        tests_create_pair::create_pair_for_test(
            alice,
            100_000_000, // 1 CETUS
            100_000_000  // 1 USDC
        ); // Initializes the add liquidity module
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        tests_assets::mint_to_address(
            cetus_addr,
            signer::address_of(alice),
            100_000_000_000, // Mint 1000 CETUS
        );
        tests_assets::mint_to_address(
            usdc_addr,
            signer::address_of(alice),
            100_000_000_000, // Mint 1000 USDC
        );
        let lp_nft_addr = tests_add_liquidity::add_liquidity_for_test(
            alice,
            100_000_000, // 1 CETUS
            100_000_000   // 1 USDC
        ); // Initializes the add liquidity module
        // Mint some cetus and usdc to Alice
        let (cetus_addr, usdc_addr, _, _) = tests_assets::get_test_fas();
        for (i in 0..9) {
            swap::swap(
                alice, // Sender is Alice
                0, // Pool ID
                10_000, // Amount of token CETUS to swap (1 CETUS)
                true,
                signer::address_of(bob), // Recipient is Alice
                0, // Minimum amount of token USDC to receive (0 USDC)
                0, // Minimum amount of token ciUSDC to receive (0 ciUSDC)
            );
            let get_product_reserves_sqrt = swap::get_product_reserves_sqrt(0);
            let get_product_balances_sqrt = swap::get_product_balances_sqrt(0);
            //debug::print(&get_product_reserves_sqrt);
            //debug::print(&get_product_balances_sqrt);
            let (
                global_x_fee_growth_x128,
                global_y_fee_growth_x128,
                global_debt_x_fee_growth_x128,
                global_debt_y_fee_growth_x128
            ) = swap::get_global_fees_growth(0); // Get the fees for pool ID 0
            let (
                k_sqrt_added,
                x_fee_growth_inside_x128,
                y_fee_growth_inside_x128,
                debt_x_fee_growth_inside_y_x128,
                debt_y_fee_growth_inside_y_x128
            ) = position::get_position_info(
                0,
                signer::address_of(alice), // Alice's address
                lp_nft_addr
            );
            debug::print(&string::utf8(b"Global Fees Growth After Swap"));
            debug::print(&global_x_fee_growth_x128);
            debug::print(&global_debt_x_fee_growth_x128);
            debug::print(&global_y_fee_growth_x128);
            debug::print(&global_debt_y_fee_growth_x128);
            debug::print(&string::utf8(b"Position Info After Swap"));
            debug::print(&k_sqrt_added);
            debug::print(&x_fee_growth_inside_x128);
            debug::print(&debt_x_fee_growth_inside_y_x128);
            debug::print(&y_fee_growth_inside_x128);
            debug::print(&debt_y_fee_growth_inside_y_x128);

            assert!(
                get_product_reserves_sqrt == get_product_balances_sqrt,
                0 // The reserves and balances should be equal
            );
        }
    }
}