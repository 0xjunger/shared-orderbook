#!/usr/bin/env bash
# Test: Cancel L1-backed order → L1 collateral released
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/addresses.env"

echo ""
info "=== Test: Cancel L1-Backed Order ==="

FUNDER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Fund Charlie on L1 + L2
$CAST send --rpc-url "$L1_RPC" --private-key "$FUNDER_KEY" "$CHARLIE_ADDR" --value 20ether > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$CHARLIE_ADDR" --value 1ether > /dev/null 2>&1
sleep 13

# Charlie deposits 8 ETH to L1 Vault
info "Charlie deposits 8 ETH to L1 Vault..."
$CAST send --rpc-url "$L1_RPC" --private-key "$CHARLIE_KEY" \
    "$VAULT_ADDR" "deposit(address,uint256)" \
    "0x0000000000000000000000000000000000000000" "8000000000000000000" \
    --value 8ether > /dev/null 2>&1

# Verify + cache
$CAST send --rpc-url "$L2_RPC" --private-key "$CHARLIE_KEY" \
    "$MARGIN_ADDR" "verifyAndUpdateL1Balance(address,address)" \
    "$CHARLIE_ADDR" "0x0000000000000000000000000000000000000000" > /dev/null 2>&1
sleep 13

# Place L1-backed SELL order: 5 ETH at 4000
info "Charlie places L1-backed SELL: 5 ETH at 4000..."
$CAST send --rpc-url "$L2_RPC" --private-key "$CHARLIE_KEY" \
    "$ENGINE_ADDR" "placeLimitOrder(uint8,uint256,uint256,bool)" \
    1 "4000000000000000000000" "5000000000000000000" true \
    > /dev/null 2>&1
sleep 13

# Check: 5 locked, 3 free on L1
LOCKED=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "lockedBalance(address,address)(uint256)" "$CHARLIE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$LOCKED" "5000000000000000000" "Charlie locked before cancel"

# Get orderId (should be next available)
# Query the order directly
ORDER_DATA=$($CAST call --rpc-url "$L2_RPC" "$BOOK_ADDR" \
    "getOrder(uint256)((uint256,address,uint8,uint8,uint256,uint256,uint256,uint256,uint8,bool))" 1 2>/dev/null)
info "Order data: $ORDER_DATA"

# Cancel order (orderId = 1 for first order in this test)
# We need to find Charlie's order ID. Let's read nextOrderId to find the latest.
NEXT_ID=$($CAST call --rpc-url "$L2_RPC" "$BOOK_ADDR" "nextOrderId()(uint256)" 2>/dev/null)
CHARLIE_ORDER_ID=$((NEXT_ID - 1))
info "Cancelling order ID $CHARLIE_ORDER_ID..."

$CAST send --rpc-url "$L2_RPC" --private-key "$CHARLIE_KEY" \
    "$ENGINE_ADDR" "cancelOrder(uint256)" "$CHARLIE_ORDER_ID" \
    > /dev/null 2>&1
sleep 13

# Verify: all unlocked on L1
LOCKED_AFTER=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "lockedBalance(address,address)(uint256)" "$CHARLIE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$LOCKED_AFTER" "0" "Charlie locked after cancel"

FREE_AFTER=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "freeBalance(address,address)(uint256)" "$CHARLIE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$FREE_AFTER" "8000000000000000000" "Charlie free after cancel (all 8 ETH)"

pass "=== Cancel Order Test Complete ==="
