/// ===============================================
///  CiSwap Pool Math Utils Module
///  ----------------------------------------------
///  Mathematical utilities for pool logic and AMM calculations
/// ===============================================

/// Pool math utilities for CiSwap: provides all mathematical operations for pool logic
module ciswap::pool_math_utils {
    use aptos_framework::math128::{Self};

    /// Multiplier for virtual reserves (1.25x)
    /// Used to amplify the effect of virtual reserves in the pool's invariant.
    const VIRTUAL_MULTIPLIER: u64 = 1_250_000; // 1.25
    /// Trading fee (0.3%)
    /// Applied to every swap, deducted from the output amount.
    const FEE: u64 = 3_000; // 0.3% trading fee
    /// Portion of fee that goes to LPs (10%)
    /// The rest is protocol fee.
    const LP_FEE: u64 = 100_000; // 10% of the fee goes to LPs

    // error codes
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 0;

    /// Calculate the locked liquidity using virtual reserves.
    /// This is typically the geometric mean of debt_x and debt_y, scaled by VIRTUAL_MULTIPLIER.
    ///
    /// # Arguments
    /// - `debt_x`: Virtual reserve of X
    /// - `debt_y`: Virtual reserve of Y
    ///
    /// # Returns
    /// - `u64`: Amount of locked liquidity
    ///
    /// # Details
    /// The geometric mean ensures that both debt_x and debt_y must be nonzero for any liquidity to be locked.
    /// The multiplier amplifies the effect of virtual reserves, making the pool more liquid than it actually is.
    public fun calculate_locked_liquidity(
        debt_x: u64,
        debt_y: u64,
    ): u64 {
        // Ensure both virtual reserves are positive
        assert!(debt_x > 0 && debt_y > 0, 0);
        // Calculate the product (as u128 to avoid overflow)
        let product: u128 = (debt_x as u128) * (debt_y as u128);
        // Take the square root (geometric mean)
        let sqrt = math128::sqrt(product) as u64;
        // Scale by the virtual multiplier (amplification)
        let liquidity = sqrt * (VIRTUAL_MULTIPLIER / 1_000_000);
        liquidity
    }

    /// Returns the actual reserves (real + virtual) for both X and Y.
    ///
    /// # Returns
    /// - `(u64, u64)`: (actual_x, actual_y)
    ///
    /// # Details
    /// The actual reserves are the sum of real and virtual reserves, used in all pool math.
    public fun get_actual_x_y(
        reserve_x: u64,
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
    ): (u64, u64) {  
        let actual_x = reserve_x + reserve_debt_x;
        let actual_y = reserve_y + reserve_debt_y;
        // Both must be positive for the pool to function
        assert!(actual_x > 0 && actual_y > 0, 0);  
        (actual_x, actual_y)
    }

    /// Returns the product K = (actual_x * actual_y)
    ///
    /// # Details
    /// This is the core invariant of the pool: (X + ciX) * (Y + ciY) = K
    public fun get_k(
        reserve_x: u64,
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
    ): u128 {
        // Virtual reserves must be positive
        assert!(reserve_debt_x > 0 && reserve_debt_y > 0, 0);
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);
        let k_last = (actual_x as u128) * (actual_y as u128);
        k_last
    }

    /// Returns the square root of K (for fee and liquidity calculations)
    ///
    /// # Details
    /// Used to determine how much new liquidity is being added, and for fee distribution.
    public fun get_k_sqrt(
        reserve_x: u64,
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
    ): u64 {
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);
        let k_sqrt = math128::sqrt((actual_x as u128) * (actual_y as u128));
        (k_sqrt as u64)
    }

    /// Calculates the output amount for a given input, using the pool's invariant and fee.
    ///
    /// # Arguments
    /// - `amount_in`: Amount of input token
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_debt_x`, `reserve_debt_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Output amount after fee
    ///
    /// # Math
    /// The pool invariant is:
    ///   (X + ciX) * (Y + ciY) = K
    /// After a swap, the new reserves must satisfy the invariant.
    /// The output is calculated by solving for the new reserve after adding amount_in, then subtracting to get amount_out.
    /// Fee is applied to the output.
    public fun get_amount_out_raw(
        amount_in: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
    ): u64 {
        // Input must be positive
        assert!(amount_in > 0, 0);
        // Virtual reserves must be positive
        assert!(reserve_debt_x > 0 && reserve_debt_y > 0, 1);

        // Calculate actual reserves
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);
        let k_last = get_k(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);
        
        // Compute the raw output amount (before fee)
        let amount_out_raw: u128;
        if (x_for_y) {
            // Swapping X for Y: add to X, solve for Y
            amount_out_raw = (actual_y as u128) - math128::ceil_div(k_last, (actual_x + amount_in) as u128);
        } else {
            // Swapping Y for X: add to Y, solve for X
            amount_out_raw = (actual_x as u128) - math128::ceil_div(k_last, (actual_y + amount_in) as u128);
        };

        // Output must be positive
        assert!(amount_out_raw > 0, 2);
        // Apply fee to the output
        (amount_out_raw as u64)
    }

    /// Returns the actual and virtual output for a swap, handling the case where real reserves are insufficient.
    ///
    /// # Details
    /// If the real reserve is not enough to cover the output, the user receives the remainder as virtual tokens.
    ///
    /// # Returns
    /// - `(u64, u64)`: (real_output, debt_output)
    public fun get_amount_out(
    amount_in: u64,
    x_for_y: bool,
    reserve_x: u64,
    reserve_y: u64,
    reserve_debt_x: u64,
    reserve_debt_y: u64
    ): (
        u64, // real out 
        u64, // debt out
        u64, // real fee
        u64, // debt fee
        u64, // sqrt_k_diff,
        u64, // total_real_out
        u64 // total_debt_out
    ) {
        let total_amount_out = get_amount_out_raw(
            amount_in, 
            x_for_y, 
            reserve_x, 
            reserve_y, 
            reserve_debt_x, 
            reserve_debt_y
        );
        
        let k_sqrt_prev = get_k_sqrt(
            reserve_x, 
            reserve_y, 
            reserve_debt_x, 
            reserve_debt_y
        );

        let (amount_out_raw, amount_debt_out_raw) = if (x_for_y) {
            // If not enough real Y, return as much as possible and the rest as virtual
            if (total_amount_out > reserve_y) {
                (reserve_y, total_amount_out - reserve_y)
            } else {
                // All output can be covered by real Y
                (total_amount_out, 0)
            }
        } else {
            // If not enough real X, return as much as possible and the rest as virtual
            if (total_amount_out > reserve_x) {
                (reserve_x, total_amount_out - reserve_x)
            } else {
                // All output can be covered by real X
                (total_amount_out, 0)
            }
        };

        let amount_fee = (amount_out_raw * FEE) / 1_000_000;
        let amount_debt_fee = (amount_debt_out_raw * FEE) / 1_000_000;
        let amount_out = amount_out_raw - amount_fee;
        let debt_out = amount_debt_out_raw - amount_debt_fee;

        let k_sqrt_after = if (x_for_y) {
            get_k_sqrt(
                reserve_x + amount_in, 
                reserve_y - amount_out, 
                reserve_debt_x, 
                reserve_debt_y - debt_out
            )
        } else {
            get_k_sqrt(
                reserve_x - amount_out, 
                reserve_y + amount_in, 
                reserve_debt_x - debt_out, 
                reserve_debt_y
            )
        };
        (
            amount_out,
            debt_out,
            amount_fee,
            amount_debt_fee,
            k_sqrt_after - k_sqrt_prev,
            amount_out_raw,
            amount_debt_out_raw
        )
    }

    /// Calculates the input amount required for a desired output, using the pool's invariant and fee.
    ///
    /// # Arguments
    /// - `amount_out`: Desired output amount
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_debt_x`, `reserve_debt_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Required input amount
    ///
    /// # Math
    /// The calculation is the inverse of get_amount_out, solving for amount_in.
    public fun get_amount_in(
        amount_out: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
    ): u64 {
        // Output must be positive
        assert!(amount_out > 0, 0);
        // Virtual reserves must be positive
        assert!(reserve_debt_x > 0 && reserve_debt_y > 0, 1);

        // Calculate actual reserves
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);
        let k_last = get_k(reserve_x, reserve_y, reserve_debt_x, reserve_debt_y);

        // Compute the raw input amount (before fee)
        let amount_in_raw: u128;
        if (x_for_y) {
            // Swapping X for Y: solve for input X
            amount_in_raw = (k_last / ((actual_y - amount_out) as u128)) - (actual_x as u128);
        } else {
            // Swapping Y for X: solve for input Y
            amount_in_raw = (k_last / ((actual_x - amount_out) as u128)) - (actual_y as u128);
        };

        // Input must be positive
        assert!(amount_in_raw > 0, 2);
        // Adjust for fee
        let amount_in: u64 = (amount_in_raw as u64) * 1_000_000 / (1_000_000 - FEE); // apply fee
        amount_in
    }

    /// Quotes the amount of token Y for a given amount of token X, using the current reserves.
    ///
    /// # Arguments
    /// - `amount_x`: Amount of token X
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_debt_x`, `reserve_debt_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Quoted amount of token Y
    ///
    /// # Details
    /// This is a simple proportional quote, not accounting for slippage or fees.
    public fun quote(
        amount_x: u64, 
        reserve_x: u64, 
        reserve_y: u64,
        reserve_debt_x: u64,
        reserve_debt_y: u64,
        ): u64 {
        assert!(amount_x > 0, ERROR_INSUFFICIENT_AMOUNT);
        // Calculate actual reserves
        let (actual_x, actual_y) = get_actual_x_y(
            reserve_x, 
            reserve_y, 
            reserve_debt_x, 
            reserve_debt_y
        );
        // Proportional calculation: amount_x / actual_x * actual_y
        ((amount_x as u128) * (actual_y as u128) / (actual_x as u128)) as u64
    }

    /// Calculates the amount of real tokens to be redeemed for a given amount of virtual tokens.
    ///
    /// # Arguments
    /// - `amount`: Amount of virtual tokens
    ///
    /// # Returns
    /// - `u64`: Amount of real tokens to be redeemed
    ///
    /// # Details
    /// The redemption rate is determined by the virtual multiplier.
    public fun get_redeemed_amount(
        amount: u64,
    ): (u64) {
        amount * VIRTUAL_MULTIPLIER / 1_000_000
    }

    /// Splits a given amount into LP and fee portions.
    ///
    /// # Arguments
    /// - `amount`: Total amount to split
    ///
    /// # Returns
    /// - `(u64, u64)`: (to_lp, fee)
    ///
    /// # Details
    /// The fee is a portion of the total, the rest is credited to LPs.
    public fun get_liquidity_and_fee_amount(
        amount: u64,
    ): (u64, u64) {
        // Calculate the fee portion
        let fee = (amount * LP_FEE) / 1_000_000; // 10% of the fee goes to LPs
        // The rest is credited to LPs as liquidity
        let to_lp = amount - fee; // the rest is locked liquidity
        (to_lp, fee)
    }

    public fun get_collected_fee_amount(
        fee_delta: u128,
        k_sqrt_added: u64,
        total_k_sqrt: u64,
    ): (u64) {
        // Calculate the collected fee based on the liquidity share and total k_sqrt
        (fee_delta * (k_sqrt_added as u128) / (total_k_sqrt as u128)) as u64
    }

    public fun get_extracted_fees(
        fee_amount: u64,
    ): (u64, u64) {
        let protocol_fee = (fee_amount * LP_FEE) / 1_000_000; // 90% goes to protocol
        let lp_fee = fee_amount - protocol_fee; // 10% goes to LPs
        (protocol_fee, lp_fee)
    }
}