#!/usr/bin/env bash
# Deploy all shared orderbook contracts to SRC devnet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FORGE="/Users/junger/.foundry/bin/forge"
CAST="/Users/junger/.foundry/bin/cast"

info "Checking devnet health..."
$CAST block-number --rpc-url "$L1_RPC" > /dev/null 2>&1 || fail "L1 not reachable at $L1_RPC"
$CAST block-number --rpc-url "$L2_RPC" > /dev/null 2>&1 || fail "L2 not reachable at $L2_RPC"
pass "Devnet is reachable"

# Dev accounts are pre-funded on reth --dev L1 (1M ETH each for #0-#9)
pass "Deployer pre-funded on L1 (reth --dev)"

# Build
info "Building contracts..."
cd "$PROJECT_DIR"
$FORGE build --root "$PROJECT_DIR" > /dev/null 2>&1
pass "Contracts compiled"

# Helper: deploy and extract address from tx receipt
deploy() {
    local rpc="$1" key="$2" contract="$3"
    shift 3
    local json
    json=$($FORGE create --root "$PROJECT_DIR" --rpc-url "$rpc" --private-key "$key" --broadcast "$contract" "$@" 2>/dev/null)
    # Get tx hash from JSON
    local tx_hash
    tx_hash=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['transaction'].get('hash',''))" 2>/dev/null || true)
    if [ -z "$tx_hash" ]; then
        # Compute contract address from deployer nonce
        local from_addr
        from_addr=$($CAST wallet address --private-key "$key" 2>/dev/null)
        local nonce
        nonce=$($CAST nonce --rpc-url "$rpc" "$from_addr" 2>/dev/null)
        # Address was deployed at nonce-1
        $CAST compute-address "$from_addr" --nonce $((nonce - 1)) 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}'
    else
        sleep 2
        $CAST receipt --rpc-url "$rpc" "$tx_hash" contractAddress 2>/dev/null
    fi
}

# --- Deploy L1 Contracts ---
info "Deploying Vault.sol to L1..."
VAULT_ADDR=$(deploy "$L1_RPC" "$DEPLOYER_KEY" src/l1/Vault.sol:Vault)
[ -n "$VAULT_ADDR" ] || fail "Vault deploy failed"
pass "Vault deployed at $VAULT_ADDR"

info "Deploying SettlementL1.sol to L1..."
SETTLEMENT_L1_ADDR=$(deploy "$L1_RPC" "$DEPLOYER_KEY" src/l1/SettlementL1.sol:SettlementL1 --constructor-args "$VAULT_ADDR")
[ -n "$SETTLEMENT_L1_ADDR" ] || fail "SettlementL1 deploy failed"
pass "SettlementL1 deployed at $SETTLEMENT_L1_ADDR"

info "Authorizing SettlementL1 on Vault..."
$CAST send --rpc-url "$L1_RPC" --private-key "$DEPLOYER_KEY" \
    "$VAULT_ADDR" "setAuthorized(address,bool)" "$SETTLEMENT_L1_ADDR" true > /dev/null 2>&1
pass "SettlementL1 authorized"

# --- Deploy L2 Contracts ---
FUNDER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
info "Funding deployer on L2..."
$CAST send --rpc-url "$L2_RPC" --private-key "$FUNDER_KEY" "$DEPLOYER_ADDR" --value 100ether > /dev/null 2>&1 || info "L2 funding skipped (may already be funded)"
sleep 13
pass "Deployer ready on L2"

info "Deploying MarginL2.sol to L2..."
MARGIN_ADDR=$(deploy "$L2_RPC" "$DEPLOYER_KEY" src/l2/MarginL2.sol:MarginL2)
[ -n "$MARGIN_ADDR" ] || fail "MarginL2 deploy failed"
pass "MarginL2 deployed at $MARGIN_ADDR"

info "Deploying OrderBook.sol to L2..."
BOOK_ADDR=$(deploy "$L2_RPC" "$DEPLOYER_KEY" src/l2/OrderBook.sol:OrderBook)
[ -n "$BOOK_ADDR" ] || fail "OrderBook deploy failed"
pass "OrderBook deployed at $BOOK_ADDR"

info "Deploying SettlementL2.sol to L2..."
SETTLEMENT_L2_ADDR=$(deploy "$L2_RPC" "$DEPLOYER_KEY" src/l2/SettlementL2.sol:SettlementL2 --constructor-args "$MARGIN_ADDR")
[ -n "$SETTLEMENT_L2_ADDR" ] || fail "SettlementL2 deploy failed"
pass "SettlementL2 deployed at $SETTLEMENT_L2_ADDR"

# ETH as both base and quote for simplicity on devnet
WETH="0x0000000000000000000000000000000000000000"
USDC="0x0000000000000000000000000000000000000000"

info "Deploying MatchingEngine.sol to L2..."
ENGINE_ADDR=$(deploy "$L2_RPC" "$DEPLOYER_KEY" src/l2/MatchingEngine.sol:MatchingEngine \
    --constructor-args "$BOOK_ADDR" "$SETTLEMENT_L2_ADDR" "$MARGIN_ADDR" "$WETH" "$USDC")
[ -n "$ENGINE_ADDR" ] || fail "MatchingEngine deploy failed"
pass "MatchingEngine deployed at $ENGINE_ADDR"

# Wire L2 permissions
info "Wiring L2 permissions..."
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$BOOK_ADDR" "setMatchingEngine(address)" "$ENGINE_ADDR" > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$MARGIN_ADDR" "setMatchingEngine(address)" "$ENGINE_ADDR" > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$MARGIN_ADDR" "setSettlement(address)" "$SETTLEMENT_L2_ADDR" > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$SETTLEMENT_L2_ADDR" "setMatchingEngine(address)" "$ENGINE_ADDR" > /dev/null 2>&1
pass "L2 permissions wired"

# Cross-chain proxy setup
info "Setting cross-chain proxy references..."
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$SETTLEMENT_L2_ADDR" "setSettlementL1Proxy(address)" "$SETTLEMENT_L1_ADDR" > /dev/null 2>&1
$CAST send --rpc-url "$L2_RPC" --private-key "$DEPLOYER_KEY" "$MARGIN_ADDR" "setSettlementL1Proxy(address)" "$SETTLEMENT_L1_ADDR" > /dev/null 2>&1
$CAST send --rpc-url "$L1_RPC" --private-key "$DEPLOYER_KEY" "$SETTLEMENT_L1_ADDR" "setAuthorizedProxy(address,bool)" "$SETTLEMENT_L2_ADDR" true > /dev/null 2>&1
pass "Cross-chain proxies configured"

# Save addresses
cat > "$SCRIPT_DIR/addresses.env" << EOF
VAULT_ADDR=$VAULT_ADDR
SETTLEMENT_L1_ADDR=$SETTLEMENT_L1_ADDR
MARGIN_ADDR=$MARGIN_ADDR
BOOK_ADDR=$BOOK_ADDR
SETTLEMENT_L2_ADDR=$SETTLEMENT_L2_ADDR
ENGINE_ADDR=$ENGINE_ADDR
EOF

echo ""
echo "=========================================="
echo "  Shared Orderbook Deployed Successfully"
echo "=========================================="
echo "L1: Vault=$VAULT_ADDR  SettlementL1=$SETTLEMENT_L1_ADDR"
echo "L2: OrderBook=$BOOK_ADDR  Engine=$ENGINE_ADDR"
echo "    MarginL2=$MARGIN_ADDR  SettlementL2=$SETTLEMENT_L2_ADDR"
echo "Saved to: $SCRIPT_DIR/addresses.env"
