/// Type utilities for CiSwap: provides type comparison and sorting helpers
module ciswap::types_utils {
    use aptos_std::comparator::{Self};
    use aptos_std::string::{Self};
    use aptos_std::type_info::{Self};

    /// Enum for comparison results between types
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
    fun compare_struct<X, Y>(): Comparison {
        let struct_x_bytes: vector<u8> = get_token_info<X>();
        let struct_y_bytes: vector<u8> = get_token_info<Y>();
        if (comparator::is_greater_than(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            Comparison::Greater
        } else if (comparator::is_equal(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            Comparison::Equal
        } else {
            Comparison::Small
        }
    }

    /// Returns the byte representation of a type's name
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
    public fun sort_token_type<X, Y>(): bool {
        let compare_x_y = compare_struct<X, Y>();
        assert!(compare_x_y != Comparison::Equal, ERROR_SAME_COIN);
        (compare_x_y == Comparison::Small)
    }
}   