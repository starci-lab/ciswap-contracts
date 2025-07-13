# 💧 Virtual Liquidity in CiSwap (Transferable Debt Tokens)

CiSwap implements **Virtual Liquidity** to enable swaps even when one side of a trading pair is depleted. This is achieved through **transferable debt tokens** like `ciAPT` and `ciUSDC`.

## 📦 How It Works

1. **Pool Initialization**
   - When a new pool is created (e.g., APT/USDC):
     - `ciAPT` and `ciUSDC` are minted to represent virtual liquidity.
     - These are IOU-style tokens backed by future real liquidity.

2. **Swap Behavior**
   - If a user swaps USDC → APT and the pool has no APT:
     - The protocol mints and returns `ciAPT`.
     - `ciAPT` is a transferable debt token representing a claim on APT.

3. **Redemption**
   - When the pool is later replenished with APT:
     - Users holding `ciAPT` can redeem it for real APT.

## 🔄 Token Behavior

- `ciTokens` are **transferable**, enabling:
  - **Peer-to-peer trading**
  - **Secondary market listing**
  - **Use as collateral in DeFi**
- They follow the standard Aptos `coin` interface and include mint/redeem logic.

## 🧠 Design Benefits

- Keeps swap functionality alive even in imbalanced pools.
- Makes capital usage more efficient.
- Enables building financial primitives on top of `ciTokens` (e.g., lending markets, vaults).

## 📊 Example Flow

| Action                    | User Receives |
|---------------------------|---------------|
| Swap 1,000 USDC → APT     | 3.25 `ciAPT`  |
| Later pool is refilled    | Can redeem 3.25 `ciAPT` for APT |
| Or: sell/trade `ciAPT`    | Optional      |

## 🚀 Future Extensions

- Dynamic interest/yield on debt tokens
- Auction-based redemption or liquidation
- Staking `ciTokens` for protocol rewards
