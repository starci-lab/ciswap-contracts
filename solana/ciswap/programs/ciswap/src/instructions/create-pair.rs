use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount};
use anchor_spl::token_interface::TokenAccount as TokenAccountInterface;

use crate::errors::ErrorCode;
use crate::events::*;
use crate::manager::liquidity_manager::{
    calculate_liquidity_token_deltas, calculate_modify_liquidity, sync_modify_liquidity_values,
};
use crate::manager::tick_array_manager::update_tick_array_accounts;
use crate::math::convert_to_liquidity_delta;
use crate::state::*;
use crate::util::{
    to_timestamp_u64, transfer_from_owner_to_vault, verify_position_authority_interface,
};

#[derive(Accounts)]
pub struct CreatePairCtx<'info> {
    #[account(
        init,
        payer = signer,
        space = 8 + std::mem::size_of::<Pool>(),
        seeds = [b"pool", token_x.key().as_ref(), token_y.key().as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,

    #[account(mut)]
    pub signer: Signer<'info>, // Signer of the transaction
}

pub fn handler(
    ctx: Context<CreatePairCtx>,
    liquidity_amount: u128,
    token_max_a: u64,
    token_max_b: u64,
) -> Result<()> {
    verify_position_authority_interface(
        &ctx.accounts.position_token_account,
        &ctx.accounts.position_authority,
    )?;

    let clock = Clock::get()?;

    if liquidity_amount == 0 {
        return Err(ErrorCode::LiquidityZero.into());
    }
    let liquidity_delta = convert_to_liquidity_delta(liquidity_amount, true)?;
    let timestamp = to_timestamp_u64(clock.unix_timestamp)?;

    let tick_arrays = TickArraysMut::load(
        &ctx.accounts.tick_array_lower,
        &ctx.accounts.tick_array_upper,
        &ctx.accounts.whirlpool.key(),
    )?;

    let (lower_tick_array, upper_tick_array) = tick_arrays.deref();
    let update = calculate_modify_liquidity(
        &ctx.accounts.whirlpool,
        &ctx.accounts.position,
        lower_tick_array,
        upper_tick_array,
        liquidity_delta,
        timestamp,
    )?;

    // Need to drop the tick arrays so we can potentially resize them
    drop(tick_arrays);

    update_tick_array_accounts(
        &ctx.accounts.position,
        ctx.accounts.tick_array_lower.to_account_info(),
        ctx.accounts.tick_array_upper.to_account_info(),
        &update.tick_array_lower_update,
        &update.tick_array_upper_update,
    )?;

    let mut tick_arrays = TickArraysMut::load(
        &ctx.accounts.tick_array_lower,
        &ctx.accounts.tick_array_upper,
        &ctx.accounts.whirlpool.key(),
    )?;

    let (lower_tick_array, upper_tick_array) = tick_arrays.deref_mut();
    sync_modify_liquidity_values(
        &mut ctx.accounts.whirlpool,
        &mut ctx.accounts.position,
        lower_tick_array,
        upper_tick_array,
        &update,
        timestamp,
    )?;

    let (delta_a, delta_b) = calculate_liquidity_token_deltas(
        ctx.accounts.whirlpool.tick_current_index,
        ctx.accounts.whirlpool.sqrt_price,
        &ctx.accounts.position,
        liquidity_delta,
    )?;

    if delta_a > token_max_a || delta_b > token_max_b {
        return Err(ErrorCode::TokenMaxExceeded.into());
    }

    transfer_from_owner_to_vault(
        &ctx.accounts.position_authority,
        &ctx.accounts.token_owner_account_a,
        &ctx.accounts.token_vault_a,
        &ctx.accounts.token_program,
        delta_a,
    )?;

    transfer_from_owner_to_vault(
        &ctx.accounts.position_authority,
        &ctx.accounts.token_owner_account_b,
        &ctx.accounts.token_vault_b,
        &ctx.accounts.token_program,
        delta_b,
    )?;

    emit!(LiquidityIncreased {
        whirlpool: ctx.accounts.whirlpool.key(),
        position: ctx.accounts.position.key(),
        tick_lower_index: ctx.accounts.position.tick_lower_index,
        tick_upper_index: ctx.accounts.position.tick_upper_index,
        liquidity: liquidity_amount,
        token_a_amount: delta_a,
        token_b_amount: delta_b,
        token_a_transfer_fee: 0,
        token_b_transfer_fee: 0,
    });

    Ok(())
}