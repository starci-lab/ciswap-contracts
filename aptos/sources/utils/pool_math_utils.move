// Pool math utilities for ciswap
module ciswap::pool_math_utils {
    use aptos_framework::math128::{Self};

    const VIRTUAL_MULTIPLIER: u64 = 1_250_000; // 1.25
    const FEE: u64 = 3_000; // 0.3% fee
    /// Calculate the locked liquidity using virtual reserves.
    /// This is typically the geometric mean of virtual_x and virtual_y.
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

    /// Get the amount out for a given amount in, using the formula:
    /// k = 
    /// (reserve X + 1.25 * reserve virtual X) * (reserve Y + 1.25 * reserve virtual Y)
    /// k = (reserve X + amount_in + 1.25 * reserve virtual X) 
    /// * (reserve Y + 1.25 * reserve virtual Y - amount_out)
    /// => amount_out = 
    /// reserve Y + 1.25 * reserve virtual Y 
    /// - k / (reserve X + amount_in + 1.25 * reserve virtual X)
    /// since we have fee, so that amount_out = net * (1_0000 - FEE) / 1_0000
    public fun get_actual_x_y(
        reserve_x: u64,
        reserve_y: u64,
        virtual_x: u64,
        virtual_y: u64,
    ): (u64, u64) {
        assert!(reserve_x > 0 && reserve_y > 0, 0);    
        let actual_x = reserve_x + virtual_x;
        let actual_y = reserve_y + virtual_y;
        (actual_x, actual_y)
    }

    public fun get_k_last(
        reserve_x: u64,
        reserve_y: u64,
        virtual_x: u64,
        virtual_y: u64,
    ): u128 {
        assert!(virtual_x > 0 && virtual_y > 0, 0);
        assert!(reserve_x > 0 && reserve_y > 0, 0);
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, virtual_x, virtual_y);
        let k_last = (actual_x as u128) * (actual_y as u128);
        k_last
    }

    /// Get the amount out for a given amount in, using the formula:
    public fun get_amount_out(
        amount_in: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        virtual_x: u64,
        virtual_y: u64,
    ): u64 {
        // get actual reserves
        assert!(amount_in > 0, 0);
        assert!(virtual_x > 0 && virtual_y > 0, 1);

        // check if reserves are valid
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, virtual_x, virtual_y);
        let k_last = get_k_last(reserve_x, reserve_y, virtual_x, virtual_y);
        
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

    // get the amount in for a given amount out, using the formula:
    public fun get_amount_in(
        amount_out: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        virtual_x: u64,
        virtual_y: u64,
    ): u64 {
        // get actual reserves
        assert!(amount_out > 0, 0);
        assert!(virtual_x > 0 && virtual_y > 0, 1);

        // check if reserves are valid
        let (actual_x, actual_y) = get_actual_x_y(reserve_x, reserve_y, virtual_x, virtual_y);
        let k_last = get_k_last(reserve_x, reserve_y, virtual_x, virtual_y);

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

    // get the amount of actual tokens out, if reserveX < amount_out
    // this is the way virtual liquidity work. You will receive virtual token if the reserve is not enough.
    public fun get_tokens_amount_out(
        amount_in: u64,
        x_for_y: bool,
        reserve_x: u64,
        reserve_y: u64,
        virtual_x: u64,
        virtual_y: u64,
    ): (u64, u64) {
       let amount_out = get_amount_out(amount_in, x_for_y, reserve_x, reserve_y, virtual_x, virtual_y);
       if (x_for_y) {
            // if reserve_x is not enough, return reserve_x and the amount in minus reserve_x
            if (amount_out > reserve_x) {
                return (reserve_x, amount_out - reserve_x);
            };
            // if reserve_x is enough, return 0 for reserve_x and the amount in for reserve_y
            return (amount_out, 0);
        };
        // if reserve_y is not enough, return reserve_y and the amount in minus reserve_y
        if (amount_out > reserve_y) {
            return (reserve_y, amount_out - reserve_y);
        };
        // if reserve_x is enough, return 0 for reserve_x and the amount in for reserve_y
        (amount_out, 0)
    }

    // get the amount of tokens when virtual tokens return back into the pool
    public fun get_redeemed_amount(
        amount: u64,
    ): (u64) {
        amount * VIRTUAL_MULTIPLIER / 1_000_000
    }
}