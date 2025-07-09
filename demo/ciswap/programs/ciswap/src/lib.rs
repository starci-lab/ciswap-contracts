use anchor_lang::prelude::*;

declare_id!("9TjYAv9ABptiDtRhiFrLMGw4VQdwUGn7ivpPGxXre1Kp");

#[doc(hidden)]
pub mod errors;
#[doc(hidden)]
pub mod instructions;

use instructions::*;

#[program]
pub mod ciswap {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        msg!("Greetings from: {:?}", ctx.program_id);
        Ok(())
    }

    pub fn hello_anchor(
        ctx: Context<HelloAnchorCtx>,
        msg: String,
    ) -> Result<()> {
        instructions::hello_anchor::handler(
            ctx,
            msg,
            Clock::get()?.unix_timestamp
        )
    }
}

#[derive(Accounts)]
pub struct Initialize {}
