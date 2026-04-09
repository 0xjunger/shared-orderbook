#!/usr/bin/env bash
# Test: Cross-chain trade (L1-backed maker, taker fills via L1 Vault)
# Alice deposits WETH to L1 Vault, places L1-backed sell order on L2.
# Bob deposits USDC to L1 Vault, buys via market order — atomic settlement.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/addresses.env"

echo ""
info "=== Test: Cross-Chain Trade ==="

# Fund accounts on L1
FUNDER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
$CAST send --rpc-url "$L1_RPC" --private-key "$FUNDER_KEY" "$ALICE_ADDR" --value 20ether > /dev/null 2>&1
$CAST send --rpc-url "$L1_RPC" --private-key "$FUNDER_KEY" "$BOB_ADDR" --value 20ether > /dev/null 2>&1
# Fund on L2 for gas
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$ALICE_ADDR" --value 1ether > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$BOB_ADDR" --value 1ether > /dev/null 2>&1
sleep 13

# Step 1: Alice deposits 10 ETH to L1 Vault
info "Step 1: Alice deposits 10 ETH to L1 Vault..."
$CAST send --rpc-url "$L1_RPC" --private-key "$ALICE_KEY" \
    "$VAULT_ADDR" "deposit(address,uint256)" \
    "0x0000000000000000000000000000000000000000" "10000000000000000000" \
    --value 10ether > /dev/null 2>&1

ALICE_VAULT_FREE=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "freeBalance(address,address)(uint256)" "$ALICE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$ALICE_VAULT_FREE" "10000000000000000000" "Alice L1 Vault free"

# Step 2: Alice verifies L1 balance on L2 (cache refresh)
info "Step 2: Alice verifies L1 balance on L2..."
$CAST send --rpc-url "$L2_RPC" --private-key "$ALICE_KEY" \
    "$MARGIN_ADDR" "verifyAndUpdateL1Balance(address,address)" \
    "$ALICE_ADDR" "0x0000000000000000000000000000000000000000" > /dev/null 2>&1
sleep 13

L1_CACHE=$($CAST call --rpc-url "$L2_RPC" "$MARGIN_ADDR" \
    "l1FreeCache(address,address)(uint256)" \
    "0x0000000000000000000000000000000000000000" "$ALICE_ADDR" 2>/dev/null)
assert_eq "$L1_CACHE" "10000000000000000000" "Alice L1 cache on L2"

# Step 3: Alice places L1-backed SELL order: 5 ETH at 3000
info "Step 3: Alice places L1-backed SELL limit: 5 ETH at 3000..."
$CAST send --rpc-url "$L2_RPC" --private-key "$ALICE_KEY" \
    "$ENGINE_ADDR" "placeLimitOrder(uint8,uint256,uint256,bool)" \
    1 "3000000000000000000000" "5000000000000000000" true \
    > /dev/null 2>&1
sleep 13

# Verify L1 Vault lock
ALICE_LOCKED=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "lockedBalance(address,address)(uint256)" "$ALICE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$ALICE_LOCKED" "5000000000000000000" "Alice L1 Vault locked"

ALICE_FREE=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "freeBalance(address,address)(uint256)" "$ALICE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$ALICE_FREE" "5000000000000000000" "Alice L1 Vault free after lock"

# Step 4: Bob deposits 10 ETH to L1 Vault (as quote token / taker's collateral)
info "Step 4: Bob deposits 10 ETH to L1 Vault..."
$CAST send --rpc-url "$L1_RPC" --private-key "$BOB_KEY" \
    "$VAULT_ADDR" "deposit(address,uint256)" \
    "0x0000000000000000000000000000000000000000" "10000000000000000000" \
    --value 10ether > /dev/null 2>&1

# Step 5: Bob buys 3 ETH via market order
info "Step 5: Bob places market BUY for 3 ETH..."
$CAST send --rpc-url "$L2_RPC" --private-key "$BOB_KEY" \
    "$ENGINE_ADDR" "placeMarketOrder(uint8,uint256)" \
    0 "3000000000000000000" \
    > /dev/null 2>&1
sleep 13

# Verify L1 Vault state after cross-chain settlement
info "Verifying L1 Vault state after settlement..."

# Alice: 5 locked - 3 unlocked = 2 locked, 5 + received quote = more free
ALICE_LOCKED_AFTER=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "lockedBalance(address,address)(uint256)" "$ALICE_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
assert_eq "$ALICE_LOCKED_AFTER" "2000000000000000000" "Alice locked after fill (2 ETH remaining)"

# Bob: received 3 ETH in Vault
BOB_WETH=$($CAST call --rpc-url "$L1_RPC" "$VAULT_ADDR" \
    "freeBalance(address,address)(uint256)" "$BOB_ADDR" \
    "0x0000000000000000000000000000000000000000" 2>/dev/null)
info "Bob L1 Vault ETH balance: $BOB_WETH"

pass "=== Cross-Chain Trade Test Complete ==="
