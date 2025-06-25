// Pool math utilities for ciswap
module ciswap::types_utils {
    use aptos_std::comparator::{Self};
    use aptos_std::string::{Self};
    use aptos_std::type_info::{Self};

    // enum like comparison
    enum Comparison has drop, copy {
        Equal,
        Small,
        Greater
    }

    const ERROR_SAME_COIN: u64 = 3;

    // convert Struct to bytes ,then compare
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

    public fun get_token_info<T>(): vector<u8> {
        let type_name = type_info::type_name<T>();
        *string::bytes(&type_name)
    }

    public fun sort_token_type<X, Y>(): bool {
        let compare_x_y = compare_struct<X, Y>();
        assert!(compare_x_y != Comparison::Equal, ERROR_SAME_COIN);
        (compare_x_y == Comparison::Small)
    }
}   