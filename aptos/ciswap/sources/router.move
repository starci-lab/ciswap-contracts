// ===============================================
//  CiSwap Router Module
//  ----------------------------------------------
//  Provides entry points for users to interact with the swap module
// ===============================================

// This module is intended to provide user-facing entry points for interacting with the CiSwap protocol.
// All functions are commented out, but the comments explain their intended use and logic.
// No state is changed by any function in this module.

/// Router module for CiSwap: provides entry points for users to interact with the swap module
module ciswap::router {
    // Import the swap module for all core pool logic
    use ciswap::swap::{Self};
    /// Error code for pair not created
    const E_PAIR_NOT_CREATED: u64 = 0;

    /// Entry point to perform a swap between two tokens in a pool
    ///
    /// # Type Parameters
    /// - `X`: Type of the input token
    /// - `Y`: Type of the output token
    ///
    /// # Arguments
    /// - `sender`: The signer performing the swap
    /// - `pool_addr`: Address of the pool
    /// - `amount_in`: Amount of input token to swap
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `recipient_addr`: Address to receive the output tokens
    /// - `limit_amount_calculated`: Slippage protection (max output allowed)
    ///
    /// # Details
    /// This function checks that the pool exists, then calls the swap logic in the swap module.
    public entry fun swap(
        sender: &signer,
        pool_id: u64,
        amount_in: u64,
        x_for_y: bool,
        recipient_addr: address,
        limit_amount_calculated: u64,
        limit_debt_amount_calculated: u64
    ) {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's swap function
        swap::swap(
            sender,
            pool_id,
            amount_in,
            x_for_y,
            recipient_addr,
            limit_amount_calculated,
            limit_debt_amount_calculated
        );
    }

    /// Entry point to create a new token pair pool
    ///
    /// # Type Parameters
    /// - `X`: Type of the first token
    /// - `Y`: Type of the second token
    ///
    /// # Arguments
    /// - `sender`: The signer creating the pair
    /// - `pool_addr`: Address of the new pool
    /// - `virtual_x`: Initial virtual X liquidity
    /// - `virtual_y`: Initial virtual Y liquidity
    ///
    /// # Details
    /// This function checks that the pool does not already exist, then calls the create_pair logic in the swap module.
    public entry fun create_pair(
        sender: &signer,
        address_x: address, // Address of token X
        address_y: address, // Address of token Y
        amount_debt_x: u64, // Initial virtual X liquidity
        amount_debt_y: u64  // Initial virtual Y liquidity
    ) {
        // Call the swap module's create_pair function
        swap::create_pair(
            sender,
            address_x, // Address of token X
            address_y, // Address of token Y
            amount_debt_x, // Initial virtual X liquidity
            amount_debt_y  // Initial virtual Y liquidity
        );
    }

    /// Entry point to add liquidity to an existing pool
    ///
    /// # Type Parameters
    /// - `X`: Type of the first token
    /// - `Y`: Type of the second token
    ///
    /// # Arguments
    /// - `sender`: The signer adding liquidity
    /// - `pool_addr`: Address of the pool
    /// - `amount_x`: Amount of token X to add
    /// - `amount_y`: Amount of token Y to add
    ///
    /// # Details
    /// This function checks that the pool exists, then calls the add_liquidity logic in the swap module.
    public entry fun add_liquidity(
        sender: &signer,
        pool_id: u64,
        amount_x: u64,
        amount_y: u64,
    ) {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's add_liquidity function
        swap::add_liquidity(
            sender,
            pool_id,
            amount_x,
            amount_y,
        );
    }

    /// Entry point to redeem virtual tokens for real tokens from a pool
    ///
    /// # Type Parameters
    /// - `X`: Type of the first token
    /// - `Y`: Type of the second token
    ///
    /// # Arguments
    /// - `sender`: The signer redeeming tokens
    /// - `pool_addr`: Address of the pool
    /// - `amount_virtual_x`: Amount of virtual X to redeem
    /// - `amount_virtual_y`: Amount of virtual Y to redeem
    /// - `recipient_addr`: Address to receive the real tokens
    ///
    /// # Details
    /// This function checks that the pool exists, then calls the redeem logic in the swap module.
    public entry fun redeem(
        sender: &signer,
        pool_id: u64,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
        recipient_addr: address
    ) {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's redeem function
        swap::redeem(
            sender,
            pool_id,
            amount_virtual_x,
            amount_virtual_y,
            recipient_addr
        );
    }

    /// Collect fees from a pool
    public entry fun collect_fees(
        sender: &signer,
        pool_id: u64,
        recipient_addr: address
    ) {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's collect_fees function
        swap::collect_fees(
            sender,
            pool_id,
            recipient_addr
        );
    }
}