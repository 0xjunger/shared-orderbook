#!/usr/bin/env bash
# Run all E2E tests against SRC devnet.
# Prerequisites: SRC devnet running, contracts deployed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "=========================================="
echo "  Shared Orderbook E2E Test Suite"
echo "=========================================="
echo ""

# Check devnet
info "Checking devnet availability..."
$CAST block-number --rpc-url "$L1_RPC" > /dev/null 2>&1 || fail "L1 not reachable"
$CAST block-number --rpc-url "$L2_RPC" > /dev/null 2>&1 || fail "L2 not reachable"
pass "Devnet is up"

# Check addresses file
if [ ! -f "$SCRIPT_DIR/addresses.env" ]; then
    fail "addresses.env not found. Run deploy_orderbook.sh first."
fi
source "$SCRIPT_DIR/addresses.env"
pass "Contract addresses loaded"

echo ""

# Run tests sequentially (SRC builder handles one batch at a time)
bash "$SCRIPT_DIR/test_local_trade.sh"
echo ""

bash "$SCRIPT_DIR/test_cross_chain_trade.sh"
echo ""

bash "$SCRIPT_DIR/test_cancel_order.sh"
echo ""

echo "=========================================="
echo "  All E2E Tests Passed!"
echo "=========================================="
