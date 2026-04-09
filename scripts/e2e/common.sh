#!/usr/bin/env bash
set -euo pipefail

# SRC devnet ports (testnet-eez)
export L1_RPC="http://localhost:9555"
export L2_RPC="http://localhost:9545"
export L1_PROXY_RPC="http://localhost:9556"
export L2_PROXY_RPC="http://localhost:9548"
export HEALTH_URL="http://localhost:9560/health"

export PATH="/Applications/Docker.app/Contents/Resources/bin:/Users/junger/.foundry/bin:$PATH"
export CAST="cast"
export FORGE="forge"

# Dev accounts (from SRC HD mnemonic: test test test test test test test test test test test junk)
# Using keys #15-#18 range to avoid conflicts with SRC's own test scripts
export DEPLOYER_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"  # dev#3
export DEPLOYER_ADDR="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

export ALICE_KEY="0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e"
export ALICE_ADDR="0x976EA74026E726554dB657fA54763abd0C3a0aa9"

export BOB_KEY="0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"
export BOB_ADDR="0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"

export CHARLIE_KEY="0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97"
export CHARLIE_ADDR="0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f"

export PROJECT_DIR="/Users/junger/shared-orderbook"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Wait for value to appear (with retries)
wait_for_block() {
    local rpc=$1
    local max_wait=${2:-30}
    info "Waiting for new blocks on $rpc..."
    local start_block=$($CAST block-number --rpc-url "$rpc" 2>/dev/null || echo "0")
    for i in $(seq 1 $max_wait); do
        sleep 1
        local current=$($CAST block-number --rpc-url "$rpc" 2>/dev/null || echo "0")
        if [ "$current" -gt "$start_block" ]; then
            return 0
        fi
    done
    fail "No new blocks after ${max_wait}s"
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="$3"
    # Compare as strings (works for large numbers and hex)
    if python3 -c "exit(0 if int('$actual',0) == int('$expected',0) else 1)" 2>/dev/null; then
        pass "$msg: $actual"
    else
        fail "$msg: expected $expected, got $actual"
    fi
}

assert_gt() {
    local actual="$1"
    local threshold="$2"
    local msg="$3"
    if python3 -c "exit(0 if int('$actual') > int('$threshold') else 1)" 2>/dev/null; then
        pass "$msg: $actual > $threshold"
    else
        fail "$msg: $actual not > $threshold"
    fi
}

assert_ne() {
    local actual="$1"
    local not_expected="$2"
    local msg="$3"
    if [ "$actual" != "$not_expected" ]; then
        pass "$msg: $actual"
    else
        fail "$msg: got $actual (should not be $not_expected)"
    fi
}
