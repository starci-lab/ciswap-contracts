/// Pool math utilities for CiSwap: provides all mathematical operations for pool logic
module ciswap::pool_math_utils {
    use aptos_framework::math128::{Self};

    /// Multiplier for virtual reserves (1.25x)
    const VIRTUAL_MULTIPLIER: u64 = 1_250_000; // 1.25
    /// Trading fee (0.3%)
    const FEE: u64 = 3_000; // 0.3% trading fee
    /// Portion of fee that goes to LPs (10%)
    const LP_FEE: u64 = 10_000; // 10% of the fee goes to LPs

    // error codes
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 0;

    /// Calculate the locked liquidity using virtual reserves.
    /// This is typically the geometric mean of virtual_x and virtual_y, scaled by VIRTUAL_MULTIPLIER.
    ///
    /// # Arguments
    /// - `virtual_x`: Virtual reserve of X
    /// - `virtual_y`: Virtual reserve of Y
    ///
    /// # Returns
    /// - `u64`: Amount of locked liquidity
    public fun calculate_locked_liquidity(
        virtual_x: u64,
        virtual_y: u64,
    ): u64 {
        assert!(virtual_x > 0 && virtual_y > 0, 0);
        // Use std::math::sqrt_u128(virtual_x * virtual_y)
        let product: u128 = (virtual_x as u128) * (virtual_y as u128);
        let liquidity = (math128::sqrt(product) as u64) * (VIRTUAL_MULTIPLIER / 1_000_000);
        liquidity
    }

    /// Returns the actual reserves (real + virtual) for both X and Y
    ///
    /// # Returns
    /// - `(u64, u64)`: (actual_x, actual_y)
    public fun get_actual_x_y(
        reserve_x: u64,
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
    ): (u64, u64) {  
        let actual_x = reserve_x + reserve_virtual_x;
        let actual_y = reserve_y + reserve_virtual_y;
        assert!(actual_x > 0 && actual_y > 0, 0);  
        (actual_x, actual_y)
    }

    /// Returns the product K = (actual_x * actual_y)
    public fun get_k(
        reserve_x: u64,
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
    ): u128 {
        assert!(reserve_virtual_x > 0 && reserve_virtual_y > 0, 0);
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);
        let k_last = (actual_x as u128) * (actual_y as u128);
        k_last
    }

    /// Returns the square root of K (for fee and liquidity calculations)
    public fun get_k_sqrt(
        reserve_x: u64,
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
    ): u64 {
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);
        let k_sqrt = math128::sqrt((actual_x as u128) * (actual_y as u128));
        (k_sqrt as u64)
    }

    /// Calculates the output amount for a given input, using the pool's invariant and fee
    ///
    /// # Arguments
    /// - `amount_in`: Amount of input token
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_virtual_x`, `reserve_virtual_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Output amount after fee
    public fun get_amount_out(
        amount_in: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
    ): u64 {
        // get actual reserves
        assert!(amount_in > 0, 0);
        assert!(reserve_virtual_x > 0 && reserve_virtual_y > 0, 1);

        // check if reserves are valid
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);
        let k_last = get_k(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);
        
        // compute amount out raw
        let amount_out_raw: u128;
        if (x_for_y) {
            amount_out_raw = (actual_y as u128) - (k_last / ((actual_x + amount_in) as u128));
        } else {
            amount_out_raw = (actual_x as u128) - (k_last / ((actual_y + amount_in) as u128));
        };

        // get the amount out after fee
        assert!(amount_out_raw > 0, 2);
        let amount_out: u64 = (amount_out_raw as u64) * (1_000_000 - FEE) / 1_000_000; // apply fee
        amount_out
    }

    /// Calculates the input amount required for a desired output, using the pool's invariant and fee
    ///
    /// # Arguments
    /// - `amount_out`: Desired output amount
    /// - `x_for_y`: Direction of swap (true if X for Y)
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_virtual_x`, `reserve_virtual_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Required input amount
    public fun get_amount_in(
        amount_out: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
    ): u64 {
        // get actual reserves
        assert!(amount_out > 0, 0);
        assert!(reserve_virtual_x > 0 && reserve_virtual_y > 0, 1);

        // check if reserves are valid
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);
        let k_last = get_k(reserve_x, reserve_y, reserve_virtual_x, reserve_virtual_y);

        // compute amount in raw
        let amount_in_raw: u128;
        if (x_for_y) {
            amount_in_raw = (k_last / ((actual_y - amount_out) as u128)) - (actual_x as u128);
        } else {
            amount_in_raw = (k_last / ((actual_x - amount_out) as u128)) - (actual_y as u128);
        };

        // get the amount in after fee
        assert!(amount_in_raw > 0, 2);
        let amount_in: u64 = (amount_in_raw as u64) * 1_000_000 / (1_000_000 - FEE); // apply fee
        amount_in
    }

    /// Quotes the amount of token Y for a given amount of token X, using the current reserves
    ///
    /// # Arguments
    /// - `amount_x`: Amount of token X
    /// - `reserve_x`, `reserve_y`: Real reserves
    /// - `reserve_virtual_x`, `reserve_virtual_y`: Virtual reserves
    ///
    /// # Returns
    /// - `u64`: Quoted amount of token Y
    public fun quote(
        amount_x: u64, 
        reserve_x: u64, 
        reserve_y: u64,
        reserve_virtual_x: u64,
        reserve_virtual_y: u64,
        ): u64 {
        assert!(amount_x > 0, ERROR_INSUFFICIENT_AMOUNT);
        // get actual reserves
        let (actual_x, actual_y) = get_actual_x_y(
            reserve_x, 
            reserve_y, 
            reserve_virtual_x, 
            reserve_virtual_y
        );
        // calculate the amount of token Y for a given amount of token X
        ((amount_x as u128) * (actual_y as u128) / (actual_x as u128)) as u64
    }

    /// Splits a given amount into LP and fee portions
    ///
    /// # Arguments
    /// - `amount`: Total amount to split
    ///
    /// # Returns
    /// - `(u64, u64)`: (to_lp, fee)
    public fun get_liquidity_and_fee_amount(
        amount: u64,
    ): (u64, u64) {
        // calculate the locked liquidity
        let fee = (amount * LP_FEE) / 1_000_000; // 10% of the fee goes to LPs
        let to_lp = amount - fee; // the rest is locked liquidity
        (to_lp, fee)
    }
}