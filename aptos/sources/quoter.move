/// Quoter module for CiSwap: provides view functions to quote swap amounts without executing swaps
module ciswap::quoter {
    // Import the swap module for quoting logic
    use ciswap::swap::{Self};

    /// Calls the get_amount_out function from the swap module to quote output for a given input
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
    #[view]
    public fun get_amount_out<X, Y>(
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
    ): (u64, u64) {
        // Ensure the pair exists (throws if not)
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // Call the swap module's get_amount_out for the quote
        swap::get_amount_out<X, Y>(
            pool_addr,
            amount_in,
            x_for_y,
        )
    }

    /// Calls the get_amount_in function from the swap module to quote input required for a given output
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
    #[view]
    public fun get_amount_in<X, Y>(
        pool_addr: address,
        amount_out: u64,
        x_for_y: bool,
    ): u64 {
        // Ensure the pair exists (throws if not)
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // Call the swap module's get_amount_in for the quote
        swap::get_amount_in<X, Y>(
            pool_addr,
            amount_out,
            x_for_y,
        )
    }
}