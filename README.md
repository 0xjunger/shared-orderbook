# Shared Orderbook

Cross-chain limit order book on [Sync Rollups Composer (EEZ)](https://github.com/eez-association/sync-rollups-composer). Orders live on L2 for cheap gas and fast matching; collateral custodies on L1 for maximum security. Settlement is atomic — a single L2 transaction synchronously locks, transfers, and unlocks L1 Vault balances.

## Architecture

```
L1 (Ethereum)                          L2 (Rollup)
┌──────────────┐  ┌────────────────┐   ┌──────────────┐  ┌─────────────────┐
│  Vault.sol   │◄─┤ SettlementL1   │   │ OrderBook.sol │◄─┤ MatchingEngine  │
│              │  │                │   │              │  │                 │
│ • free/locked│  │ • settleTrade  │   │ • price-time │  │ • placeLimit   │
│ • deposit    │  │ • lockForOrder │   │ • best bid/  │  │ • placeMarket   │
│ • lock/unlock│  │ • releaseOn    │   │   ask        │  │ • cancelOrder   │
│ • transfer   │  │   Cancel       │   └──────────────┘  └────────┬────────┘
└──────────────┘  └───────┬────────┘                               │
                          │              ┌─────────────────┐  ┌────┴──────────┐
             SRC atomic cross-chain     │ MarginL2.sol    │◄─┤ SettlementL2  │
                          │              │                 │  │               │
                          └──────────────┤ • L2 balances  │  │ • settleLocal │
                                         │ • L1 cache     │  │ • settleCross │
                                         │ • depositL2    │  │   Chain       │
                                         │ • verifyL1     │  │ • lockCross   │
                                         └─────────────────┘  └───────────────┘
```

6 contracts: Vault + SettlementL1 on L1, OrderBook + MatchingEngine + MarginL2 + SettlementL2 on L2.

## How It Works

**L1-backed maker, L2-native taker** (canonical cross-chain flow):

1. Alice deposits ETH to Vault (L1)
2. Alice refreshes her L1 balance cache on L2 via `verifyAndUpdateL1Balance`
3. Alice places a sell limit order with `useL1=true` — `lockCrossChain` locks her collateral on L1 atomically
4. Bob deposits to MarginL2 (L2-native) and places a market buy
5. MatchingEngine routes Alice's fill to `settleCrossChain` (SRC proxy call to L1) and Bob's fill to `settleLocal` (L2 only)
6. Settlement happens atomically in one L2 block — no async bridging

**L2-native maker + taker**: Pure L2 settlement via `settleLocal`, no L1 involvement.

## Quick Start

```shell
forge build
forge test
```

### E2E on SRC Devnet

```shell
scripts/e2e/deploy_orderbook.sh
scripts/e2e/test_local_trade.sh
scripts/e2e/test_cross_chain_trade.sh
scripts/e2e/test_cancel_order.sh
```

## File Structure

```
src/
├── l1/Vault.sol, SettlementL1.sol          — L1 collateral + settlement
├── l2/OrderBook.sol, MatchingEngine.sol    — Order book + matching
├── l2/MarginL2.sol, SettlementL2.sol        — L2 balances + routing
├── interfaces/                              — 6 interfaces
└── libraries/OrderLib.sol                   — Structs, enums, Fill type
test/                                        — Foundry unit tests (44 tests)
scripts/e2e/                                 — SRC devnet E2E scripts
ui/                                          — React + Vite trading UI
```

## Security

- L1 is the source of truth — stale L2 cache causes transaction revert, never fund loss
- Atomic settlement via SRC — if L1 fails, L2 state reverts atomically
- Vault is `onlyAuthorized` — only SettlementL1 (via SRC proxy) can move funds
- `MAX_FILLS_PER_TX = 20` — gas-bounded matching prevents block production stalls
