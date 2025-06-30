// /// Router module for CiSwap: provides entry points for users to interact with the swap module
// module ciswap::router {
//     // Import the swap module for all core pool logic
//     use ciswap::swap::{Self};
//     /// Error code for pair not created
//     const E_PAIR_NOT_CREATED: u64 = 0;

//     /// Entry point to perform a swap between two tokens in a pool
//     ///
//     /// # Type Parameters
//     /// - `X`: Type of the input token
//     /// - `Y`: Type of the output token
//     ///
//     /// # Arguments
//     /// - `sender`: The signer performing the swap
//     /// - `pool_addr`: Address of the pool
//     /// - `amount_in`: Amount of input token to swap
//     /// - `x_for_y`: Direction of swap (true if X for Y)
//     /// - `recipient_addr`: Address to receive the output tokens
//     /// - `limit_amount_calculated`: Slippage protection (max output allowed)
//     ///
//     /// # Details
//     /// This function checks that the pool exists, then calls the swap logic in the swap module.
//     public entry fun swap<X, Y>(
//         sender: &signer,
//         pool_addr: address,
//         amount_in: u64,
//         x_for_y: bool,
//         recipient_addr: address,
//         limit_amount_calculated: u64
//     ) {
//         // Ensure the pair exists (throws if not)
//         swap::is_pair_created_internal<X, Y>(pool_addr);
//         // Call the swap module's swap function
//         swap::swap<X, Y>(
//             sender,
//             pool_addr,
//             amount_in,
//             x_for_y,
//             recipient_addr,
//             limit_amount_calculated
//         );
//     }

//     /// Entry point to create a new token pair pool
//     ///
//     /// # Type Parameters
//     /// - `X`: Type of the first token
//     /// - `Y`: Type of the second token
//     ///
//     /// # Arguments
//     /// - `sender`: The signer creating the pair
//     /// - `pool_addr`: Address of the new pool
//     /// - `virtual_x`: Initial virtual X liquidity
//     /// - `virtual_y`: Initial virtual Y liquidity
//     ///
//     /// # Details
//     /// This function checks that the pool does not already exist, then calls the create_pair logic in the swap module.
//     public entry fun create_pair<X, Y>(
//         sender: &signer,
//         pool_addr: address,
//         virtual_x: u64,
//         virtual_y: u64
//     ) {
//         // Ensure the pair does not already exist (throws if it does)
//         swap::is_pair_not_create_internal<X, Y>(pool_addr);
//         // Call the swap module's create_pair function
//         swap::create_pair<X, Y>(
//             sender,
//             pool_addr,
//             virtual_x,
//             virtual_y
//         );
//     }

//     /// Entry point to add liquidity to an existing pool
//     ///
//     /// # Type Parameters
//     /// - `X`: Type of the first token
//     /// - `Y`: Type of the second token
//     ///
//     /// # Arguments
//     /// - `sender`: The signer adding liquidity
//     /// - `pool_addr`: Address of the pool
//     /// - `amount_x`: Amount of token X to add
//     /// - `amount_y`: Amount of token Y to add
//     ///
//     /// # Details
//     /// This function checks that the pool exists, then calls the add_liquidity logic in the swap module.
//     public entry fun add_liquidity<X, Y>(
//         sender: &signer,
//         pool_addr: address,
//         amount_x: u64,
//         amount_y: u64
//     ) {
//         // Ensure the pair exists (throws if not)
//         swap::is_pair_created_internal<X, Y>(pool_addr);
//         // Call the swap module's add_liquidity function
//         swap::add_liquidity<X, Y>(
//             sender,
//             pool_addr,
//             amount_x,
//             amount_y,
//         );
//     }

//     /// Entry point to redeem virtual tokens for real tokens from a pool
//     ///
//     /// # Type Parameters
//     /// - `X`: Type of the first token
//     /// - `Y`: Type of the second token
//     ///
//     /// # Arguments
//     /// - `sender`: The signer redeeming tokens
//     /// - `pool_addr`: Address of the pool
//     /// - `amount_virtual_x`: Amount of virtual X to redeem
//     /// - `amount_virtual_y`: Amount of virtual Y to redeem
//     /// - `recipient_addr`: Address to receive the real tokens
//     ///
//     /// # Details
//     /// This function checks that the pool exists, then calls the redeem logic in the swap module.
//     public entry fun redeem<X, Y>(
//         sender: &signer,
//         pool_addr: address,
//         amount_virtual_x: u64,
//         amount_virtual_y: u64,
//         recipient_addr: address
//     ) {
//         // Ensure the pair exists (throws if not)
//         swap::is_pair_created_internal<X, Y>(pool_addr);
//         // Call the swap module's redeem function
//         swap::redeem<X, Y>(
//             sender,
//             pool_addr,
//             amount_virtual_x,
//             amount_virtual_y,
//             recipient_addr
//         );
//     }
// }