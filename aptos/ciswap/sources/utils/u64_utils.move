// ===============================================
//  CiSwap U64 Utils Module
//  ----------------------------------------------
//  Utilities for working with u64 values
// ===============================================

// This module provides helper functions for converting u64 values to strings and related utilities.

module ciswap::u64_utils {
    use std::string;
    use std::vector;

    public fun u64_to_string(num: u64): string::String {
        if (num == 0) {
            return string::utf8(b"0");
        };

        let digits = vector::empty<u8>();
        let n = num;
        
        while (n > 0) {
            let digit = (n % 10) as u8;
            vector::push_back(&mut digits, digit + 48); // ASCII '0' is 48
            n = n / 10;
        };

        vector::reverse(&mut digits);
        string::utf8(digits)
    }

    #[test]
    fun test_u64_to_string() {
        assert!(u64_to_string(0) == string::utf8(b"0"), 1);
        assert!(u64_to_string(123) == string::utf8(b"123"), 2);
        assert!(u64_to_string(1000000) == string::utf8(b"1000000"), 3);
    }
}