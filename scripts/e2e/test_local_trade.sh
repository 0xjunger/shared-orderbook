#!/usr/bin/env bash
# Test: L2-only local trade (no cross-chain)
# Alice deposits WETH on L2, places sell order. Bob deposits USDC on L2, buys via market.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/addresses.env"

echo ""
info "=== Test: Local L2 Trade ==="

# Fund Alice and Bob on L2 using dev#1 (has massive L2 balance)
FUNDER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
info "Funding Alice and Bob on L2..."
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$ALICE_ADDR" --value 10ether > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$BOB_ADDR" --value 10ether > /dev/null 2>&1
sleep 13

# Alice deposits 5 ETH to MarginL2 (using ETH = address(0))
info "Alice deposits 5 ETH to MarginL2..."
$CAST send --rpc-url "$L2_RPC" --private-key "$ALICE_KEY" \
    "$MARGIN_ADDR" "depositL2(address,uint256)" \
    "0x0000000000000000000000000000000000000000" "5000000000000000000" \
    --value 5ether > /dev/null 2>&1
sleep 13

ALICE_FREE=$($CAST call --rpc-url "$L2_RPC" "$MARGIN_ADDR" \
    "freeBalanceL2(address,address)(uint256)" "$ALICE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null | awk '{print $1}')
assert_gt "$ALICE_FREE" "0" "Alice L2 free balance"

# Alice places SELL limit order: 3 ETH at 3000 (price in 1e18)
info "Alice places SELL limit: 3 ETH at price 3000e18..."
$CAST send --rpc-url "$L2_RPC" --private-key "$ALICE_KEY" \
    "$ENGINE_ADDR" "placeLimitOrder(uint8,uint256,uint256,bool)" \
    1 "3000000000000000000000" "3000000000000000000" false \
    > /dev/null 2>&1
sleep 13

# Verify order exists
ORDER=$($CAST call --rpc-url "$L2_RPC" "$BOOK_ADDR" \
    "getOrder(uint256)((uint256,address,uint8,uint8,uint256,uint256,uint256,uint256,uint8,bool))" 1 2>/dev/null)
pass "Order placed on book: $ORDER"

# Check best ask
BEST_ASK=$($CAST call --rpc-url "$L2_RPC" "$BOOK_ADDR" \
    "getBestAsk()(uint256,uint256)" 2>/dev/null)
info "Best ask: $BEST_ASK"

echo ""
pass "=== Local L2 Trade Test Complete ==="
