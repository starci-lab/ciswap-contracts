
module token::token {
    //uses
    use aptos_framework::managed_coin::{ Self };
    use std::signer::{ Self };
    use token::package_manager::{ Self };
    use aptos_framework::account::{ Self };
    use aptos_framework::resource_account::{ Self };    

    //structs
    struct Token {}
    struct Setup has key {
        has_done: bool
    }


    //constants
    const DEPLOYER: address = @deployer;
    //templates
    const TEMPLATE_NAME: vector<u8> = b"UST Tether";
    const TEMPLATE_SYMBOL: vector<u8> = b"USDT";
    const TEMPLATE_DECIMALS: u8 = 8;
    const TEMPLATE_TOTAL_SUPPLY: u64 = 10000000000000000;
    
    //errors
    const ESENDER_NOT_DEPLOYER : u64 = 0;
    const ESETUP_HAS_DONE : u64 = 1;

    //functions
    fun init_module(sender: &signer) {
        // Retrieve the resource account capability for the deployer
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEPLOYER);
        // Create a signer for the resource account
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        managed_coin::initialize<Token>(
            &resource_signer,
            TEMPLATE_NAME,
            TEMPLATE_SYMBOL,
            TEMPLATE_DECIMALS,
            true
        );
        // Move the Setup resource to the resource account
        move_to(&resource_signer, Setup { has_done: false });
    }

    public(friend) entry fun setup(sender: &signer) acquires Setup {
        let signer = package_manager::get_signer();
        let has_done = &mut borrow_global_mut<Setup>(@token).has_done;

        if (signer::address_of(sender) != @deployer) abort ESENDER_NOT_DEPLOYER;
        if (*has_done) abort ESETUP_HAS_DONE;

        managed_coin::register<Token>(sender);
        managed_coin::mint<Token>(&signer, signer::address_of(sender), TEMPLATE_TOTAL_SUPPLY);

        *has_done = true;
    }

    //tests
    #[test_only]
    public fun initialize_for_test(deployer: &signer, resource_signer: &signer) {
        package_manager::initialize_for_test(deployer, resource_signer);
        init_module(resource_signer);
    }

    #[test_only]
    friend token::token_tests;
}
