// ===============================================
//  CiSwap Quoter Module
//  ----------------------------------------------
//  Provides view functions to quote swap amounts without executing swaps
// ===============================================

// This module is used to provide read-only functions for quoting swap amounts in the CiSwap protocol.
// All functions are commented out, but the comments explain their intended use and logic.
// No state is changed by any function in this module.

/// Quoter module for CiSwap: provides view functions to quote swap amounts without executing swaps
module ciswap::quoter {
    // Import the swap module for quoting logic
    use ciswap::swap::{Self};

    /// Quotes the output amount for a given input, using the swap module's logic.
    ///
    /// # Type Parameters
    /// - `X`: Type of the input token
    /// - `Y`: Type of the output token
    ///
    /// # Arguments
    /// - `pool_addr`: Address of the pool
    /// - `amount_in`: Amount of input token
    /// - `x_for_y`: Direction of swap (true if X for Y)
    ///
    /// # Returns
    /// - `(u64, u64)`: Tuple of (amount_out, amount_virtual_out)
    ///
    /// # Details
    /// This function only returns the quote, it does not perform the swap or change any state.
    #[view]
    public fun get_amount_out(
        pool_id: u64,
        amount_in: u64,
        x_for_y: bool,
    ): (u64, u64) {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's get_amount_out for the quote
        swap::get_amount_out(
            pool_id,
            amount_in,
            x_for_y,
        )
    }

    /// Quotes the input amount required for a given output, using the swap module's logic.
    ///
    /// # Type Parameters
    /// - `X`: Type of the input token
    /// - `Y`: Type of the output token
    ///
    /// # Arguments
    /// - `pool_addr`: Address of the pool
    /// - `amount_out`: Desired output amount
    /// - `x_for_y`: Direction of swap (true if X for Y)
    ///
    /// # Returns
    /// - `u64`: Required input amount
    ///
    /// # Details
    /// This function only returns the quote, it does not perform the swap or change any state.
    #[view]
    public fun get_amount_in(
        pool_id: u64,
        amount_out: u64,
        x_for_y: bool,
    ): u64 {
        // Ensure the pair exists (throws if not)
        swap::is_pool_created(pool_id);
        // Call the swap module's get_amount_in for the quote
        swap::get_amount_in(
            pool_id,
            amount_out,
            x_for_y,
        )
    }
}