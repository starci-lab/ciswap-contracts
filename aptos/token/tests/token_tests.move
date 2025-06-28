
#[test_only]
module token::token_tests {
    //uses
    use std::signer::{ Self };
    use aptos_framework::coin::{ Self };
    use token::token::{ 
        Self, 
        Token
    };

    //templates
    const TEMPLATE_TOTAL_SUPPLY: u64 = 10000000000000000;

    //errors
    const ESENDER_NOT_DEPLOYER : u64 = 0;
    const ESETUP_HAS_DONE : u64 = 1;

    //tests
    #[test(deployer = @deployer, resource_account=@token)]
    public fun test_setup(deployer: &signer, resource_account: &signer) {
        token::initialize_for_test(deployer, resource_account);
        token::setup(deployer);
        assert!(coin::balance<Token>(signer::address_of(deployer)) == TEMPLATE_TOTAL_SUPPLY, 0);
    }

    #[test(deployer = @deployer, resource_account=@token)]
    #[expected_failure(abort_code = ESETUP_HAS_DONE, location = token::token)]
    public fun test_setup_fail_due_call_setup_twice(deployer: &signer, resource_account: &signer) {
        token::initialize_for_test(deployer, resource_account);
        token::setup(deployer);
        token::setup(deployer);
    }

    #[test(deployer = @deployer, resource_account=@token, caller = @0x69)]
    #[expected_failure(abort_code = ESENDER_NOT_DEPLOYER, location = token::token)]
    public fun test_setup_fail_due_sender_not_deployer(deployer: &signer, resource_account: &signer, caller: &signer) {
        token::initialize_for_test(deployer, resource_account);
        token::setup(caller);
    }
}
