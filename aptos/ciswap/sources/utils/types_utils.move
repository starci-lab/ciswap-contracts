/// ===============================================
///  CiSwap Types Utils Module
///  ----------------------------------------------
///  Type comparison and sorting helpers for token types
/// ===============================================

/// Type utilities for CiSwap: provides type comparison and sorting helpers
module ciswap::types_utils {
    use aptos_std::comparator::{Self};
    use aptos_std::string::{Self};
    use aptos_std::type_info::{Self};

    /// Enum for comparison results between types
    ///
    /// - `Equal`: The two types are the same
    /// - `Small`: The first type is less than the second (by byte order)
    /// - `Greater`: The first type is greater than the second (by byte order)
    enum Comparison has drop, copy {
        Equal,
        Small,
        Greater
    }

    /// Error code for comparing the same coin type
    const ERROR_SAME_COIN: u64 = 3;

    /// Compares two struct types by their byte representation
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Types to compare
    ///
    /// # Returns
    /// - `Comparison`: Result of the comparison
    ///
    /// # Details
    /// This function converts the type names to bytes and compares them lexicographically.
    fun compare_struct<X, Y>(): Comparison {
        // Get the byte representation of each type's name
        let struct_x_bytes: vector<u8> = get_token_info<X>();
        let struct_y_bytes: vector<u8> = get_token_info<Y>();
        // Use the comparator module to compare the byte vectors
        if (comparator::is_greater_than(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            Comparison::Greater
        } else if (comparator::is_equal(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            Comparison::Equal
        } else {
            Comparison::Small
        }
    }

    /// Returns the byte representation of a type's name
    ///
    /// # Type Parameters
    /// - `T`: The type to get info for
    ///
    /// # Returns
    /// - `vector<u8>`: Byte representation of the type's name
    public fun get_token_info<T>(): vector<u8> {
        let type_name = type_info::type_name<T>();
        *string::bytes(&type_name)
    }

    /// Returns true if X should be sorted before Y (by type), false otherwise
    ///
    /// # Type Parameters
    /// - `X`, `Y`: Types to compare
    ///
    /// # Returns
    /// - `bool`: True if X < Y, false if X > Y
    ///
    /// # Details
    /// This is used to enforce a canonical order for token pairs in the pool.
    /// It asserts that the two types are not the same (no pool for identical tokens).
    public fun sort_token_type<X, Y>(): bool {
        let compare_x_y = compare_struct<X, Y>();
        assert!(compare_x_y != Comparison::Equal, ERROR_SAME_COIN);
        (compare_x_y == Comparison::Small)
    }
}   