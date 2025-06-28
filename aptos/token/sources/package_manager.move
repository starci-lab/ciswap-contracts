
module token::package_manager {
    //uses
    use aptos_framework::account::{ Self, SignerCapability };
    use aptos_framework::resource_account::{ Self };
    use aptos_std::smart_table::{ Self, SmartTable };
    use std::string::{ String };

    //constants
    const DEPLOYER: address = @deployer;

    #[test_only]
    use aptos_framework::account::{ create_account_for_test };
    #[test_only]
    use std::signer::{ Self };

    //structs
    struct PermissionConfig has key {
        signer_cap: SignerCapability,
        addresses: SmartTable<String, address>,
    }

    //functions
    fun init_module(sender: &signer) {
        // Retrieve the resource account capability for the deployer
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEPLOYER);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        move_to(&resource_signer, PermissionConfig {
            addresses: smart_table::new<String, address>(),
            signer_cap,
        });
    }

    public(friend) fun get_signer(): signer acquires PermissionConfig {
        let signer_cap = &borrow_global<PermissionConfig>(@token).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        let addresses = &mut borrow_global_mut<PermissionConfig>(@token).addresses;
        smart_table::add(addresses, name, object);
    }

    public fun address_exists(name: String): bool acquires PermissionConfig {
        smart_table::contains(&safe_permission_config().addresses, name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
        let addresses = &borrow_global<PermissionConfig>(@token).addresses;
        *smart_table::borrow(addresses, name)
    }

    inline fun safe_permission_config(): &PermissionConfig acquires PermissionConfig {
        borrow_global<PermissionConfig>(@token)
    }

    //setup tests
    #[test_only]
    public(friend) fun initialize_for_test(deployer: &signer, resource_signer: &signer) {
        create_account_for_test(signer::address_of(deployer));
        resource_account::create_resource_account(deployer, b"", b"");
        init_module(resource_signer);
    }

    friend token::token;
    #[test_only]
    friend token::package_manager_tests;
}
