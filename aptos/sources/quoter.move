module ciswap::quoter {
    use ciswap::swap::{Self};

    // call the get_amount_out function from swap module
    #[view]
    public fun get_amount_out<X, Y>(
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
    ): (u64, u64) {
        // check if the pair is created
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // proccess the get_amount_out
        swap::get_amount_out<X, Y>(
            pool_addr,
            amount_in,
            x_for_y,
        )
    }

    #[view]
    public fun get_amount_in<X, Y>(
        pool_addr: address,
        amount_out: u64,
        x_for_y: bool,
    ): u64 {
        // check if the pair is created
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // proccess the get_amount_out
        swap::get_amount_in<X, Y>(
            pool_addr,
            amount_out,
            x_for_y,
        )
    }
}