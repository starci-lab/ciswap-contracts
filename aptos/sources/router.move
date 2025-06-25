module ciswap::router {
    use ciswap::swap::{Self};
    const E_PAIR_NOT_CREATED: u64 = 0;

    fun is_pair_created_internal<X, Y>(){
        assert!(
            swap::is_pair_created<X, Y>() || swap::is_pair_created<Y, X>(), 
            E_PAIR_NOT_CREATED
        );
    }

    // call swap function from swap module
    public entry fun swap<X, Y>(
        sender: &signer,
        amount_in: u64,
        x_for_y: bool,
        recipient_addr: address,
        limit_amount_calculated: u64
    ) {
        // check if the pair is created
        is_pair_created_internal<X, Y>();
        // proccess the swap
        swap::swap<X, Y>(
            sender,
            amount_in,
            x_for_y,
            recipient_addr,
            limit_amount_calculated
        );
    }

    // call add_liquidity function from swap module
    public entry fun add_liquidity<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ) {
        // proccess the add_liquidity
        swap::add_liquidity<X, Y>(
            sender,
            amount_x,
            amount_y,
        );
    }

    // call the reedem function from swap module
    public entry fun redeem<X, Y>(
        sender: &signer,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
        recipient_addr: address
    ) {
        // check if the pair is created
        is_pair_created_internal<X, Y>();
        // proccess the redeem
        swap::redeem<X, Y>(
            sender,
            amount_virtual_x,
            amount_virtual_y,
            recipient_addr
        );
    }

    // call the get_amount_out function from swap module
    #[view]
    public fun get_amount_out<X, Y>(
        amount_in: u64,
        x_for_y: bool,
    ): (u64, u64) {
        // check if the pair is created
        is_pair_created_internal<X, Y>();
        // proccess the get_amount_out
        swap::get_amount_out<X, Y>(
            amount_in,
            x_for_y,
        )
    }

    #[view]
    public fun get_amount_in<X, Y>(
        amount_out: u64,
        x_for_y: bool,
    ): u64 {
        // check if the pair is created
        is_pair_created_internal<X, Y>();
        // proccess the get_amount_out
        swap::get_amount_in<X, Y>(
            amount_out,
            x_for_y,
        )
    }
}