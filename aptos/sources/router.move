module ciswap::router {
    use ciswap::swap::{Self};
    const E_PAIR_NOT_CREATED: u64 = 0;

    // call swap function from swap module
    public entry fun swap<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_in: u64,
        x_for_y: bool,
        recipient_addr: address,
        limit_amount_calculated: u64
    ) {
        // check if the pair is created
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // proccess the swap
        swap::swap<X, Y>(
            sender,
            pool_addr,
            amount_in,
            x_for_y,
            recipient_addr,
            limit_amount_calculated
        );
    }

    // call create_pair function from swap module
    public entry fun create_pair<X, Y>(
        sender: &signer,
        pool_addr: address,
        virtual_x: u64,
        virtual_y: u64
    ) {
        // check if the pair is not created
        swap::is_pair_not_create_internal<X, Y>(pool_addr);
        // proccess the create_pair
        swap::create_pair<X, Y>(
            sender,
            pool_addr,
            virtual_x,
            virtual_y
        );
    }

    // call add_liquidity function from swap module
    public entry fun add_liquidity<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_x: u64,
        amount_y: u64
    ) {
        // check if the pair is created
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // proccess the add_liquidity
        swap::add_liquidity<X, Y>(
            sender,
            pool_addr,
            amount_x,
            amount_y,
        );
    }

    // call the reedem function from swap module
    public entry fun redeem<X, Y>(
        sender: &signer,
        pool_addr: address,
        amount_virtual_x: u64,
        amount_virtual_y: u64,
        recipient_addr: address
    ) {
        // check if the pair is created
        swap::is_pair_created_internal<X, Y>(pool_addr);
        // proccess the redeem
        swap::redeem<X, Y>(
            sender,
            pool_addr,
            amount_virtual_x,
            amount_virtual_y,
            recipient_addr
        );
    }
}