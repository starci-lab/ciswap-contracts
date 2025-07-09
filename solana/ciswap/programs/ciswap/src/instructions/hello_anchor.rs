use anchor_lang::prelude::*;
use crate::errors::ErrorCode;

#[derive(Accounts)]
pub struct HelloAnchorCtx<'info> {
    #[account(
        init,
        payer = signer,
        space = 8 + std::mem::size_of::<HelloAnchor>(),
        seeds = [b"greeting", signer.key().as_ref()],
        bump
    )]
    pub hello_anchor: Account<'info, HelloAnchor>,

    #[account(mut)]
    pub signer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[account]
pub struct HelloAnchor {
    pub authority: Pubkey,
    pub message: String,
    pub timestamp: i64,
}

#[event]
pub struct AnchorHelloEvent {
    pub user: Pubkey,
    pub message: String,
    pub timestamp: i64,
}

pub fn handler(
    ctx: Context<HelloAnchorCtx>,
    message: String,
    timestamp: i64,
) -> Result<()> {
    // Check message not empty
    if message.trim().is_empty() {
        return Err(error!(ErrorCode::EmptyHelloAnchorMessage));
    }

    // Assign authority and message to the greeting account
    let hello_anchor = &mut ctx.accounts.hello_anchor;
    hello_anchor.authority = ctx.accounts.signer.key();
    hello_anchor.message = message.clone();
    hello_anchor.timestamp = timestamp;

    // Emit event
    emit!(AnchorHelloEvent {
        user: hello_anchor.authority,
        message,
        timestamp,
    });
    Ok(())
}