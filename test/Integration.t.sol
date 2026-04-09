// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Vault} from "../src/l1/Vault.sol";
import {SettlementL1} from "../src/l1/SettlementL1.sol";
import {OrderBook} from "../src/l2/OrderBook.sol";
import {MatchingEngine} from "../src/l2/MatchingEngine.sol";
import {MarginL2} from "../src/l2/MarginL2.sol";
import {SettlementL2} from "../src/l2/SettlementL2.sol";
import {OrderLib} from "../src/libraries/OrderLib.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount && allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice In Foundry tests, we simulate SRC's cross-chain proxy by deploying
/// all contracts in the same EVM. SettlementL1 is the "proxy target" —
/// SettlementL2 calls it directly. SettlementL1 authorizes SettlementL2 as a proxy.
/// This mirrors SRC's behavior where the proxy forwards calls transparently.
contract IntegrationTest is Test {
    // L1 contracts
    Vault vault;
    SettlementL1 settlementL1;

    // L2 contracts
    OrderBook book;
    MatchingEngine engine;
    MarginL2 margin;
    SettlementL2 settlement;

    // Tokens (deployed in test EVM, used by both "chains")
    MockERC20 weth;
    MockERC20 usdc;

    address alice = makeAddr("alice"); // maker (L1 collateral)
    address bob = makeAddr("bob");     // taker (L1 or L2 collateral)

    function setUp() public {
        // Deploy tokens
        weth = new MockERC20("Wrapped Ether", "WETH");
        usdc = new MockERC20("USD Coin", "USDC");

        // --- L1 Setup ---
        vault = new Vault();
        settlementL1 = new SettlementL1(address(vault));
        vault.setAuthorized(address(settlementL1), true);

        // --- L2 Setup ---
        book = new OrderBook();
        margin = new MarginL2();
        settlement = new SettlementL2(address(margin));
        engine = new MatchingEngine(
            address(book),
            address(settlement),
            address(margin),
            address(weth),
            address(usdc)
        );

        // Wire L2 permissions
        book.setMatchingEngine(address(engine));
        margin.setMatchingEngine(address(engine));
        margin.setSettlement(address(settlement));
        settlement.setMatchingEngine(address(engine));

        // --- Cross-chain proxy simulation ---
        // In SRC, SettlementL2 calls a cross-chain proxy that forwards to SettlementL1.
        // In tests, we point SettlementL2 directly at SettlementL1 and authorize SettlementL2.
        settlement.setSettlementL1Proxy(address(settlementL1));
        margin.setSettlementL1Proxy(address(settlementL1));
        settlementL1.setAuthorizedProxy(address(settlement), true);
    }

    // --- Helper: deposit to L1 Vault ---
    function _vaultDeposit(address user, MockERC20 token, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.stopPrank();
    }

    // --- Helper: deposit to L2 Margin ---
    function _l2Deposit(address user, MockERC20 token, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(margin), amount);
        margin.depositL2(address(token), amount);
        vm.stopPrank();
    }

    // ========================================
    // Test 1: L1 deposit → verify cache → place L1-backed order
    // ========================================
    function test_depositAndL1BackedOrder() public {
        // Alice deposits 10 WETH to L1 Vault
        _vaultDeposit(alice, weth, 10e18);
        assertEq(vault.freeBalance(alice, address(weth)), 10e18);

        // Alice verifies L1 balance on L2 (cross-chain read)
        vm.prank(alice);
        (uint256 free, uint256 locked) = margin.verifyAndUpdateL1Balance(alice, address(weth));
        assertEq(free, 10e18);
        assertEq(locked, 0);
        assertEq(margin.l1FreeCache(address(weth), alice), 10e18);

        // Alice places L1-backed SELL limit order for 3 WETH at 3000 USDC
        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(
            OrderLib.Side.SELL, 3000e18, 3e18, true
        );
        assertGt(orderId, 0);

        // Verify L1 Vault: 3 WETH locked, 7 WETH free
        assertEq(vault.lockedBalance(alice, address(weth)), 3e18);
        assertEq(vault.freeBalance(alice, address(weth)), 7e18);

        // Verify L2 cache updated
        assertEq(margin.l1FreeCache(address(weth), alice), 7e18);
        assertEq(margin.l1LockedCache(address(weth), alice), 3e18);

        // Verify order on book
        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(o.quantity, 3e18);
        assertTrue(o.isL1Backed);
    }

    // ========================================
    // Test 2: Cross-chain trade — L1-backed maker, L1 taker
    // ========================================
    function test_crossChainTrade() public {
        // Alice: maker, deposits WETH to L1, sells 3 WETH at 3000
        _vaultDeposit(alice, weth, 5e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, true);

        // Bob: taker, deposits USDC to L1 Vault (needs it for cross-chain settlement)
        _vaultDeposit(bob, usdc, 10000e18);

        // Bob buys 2 WETH via market order
        // For market orders against L1-backed maker, settlement happens cross-chain.
        // Bob needs USDC in L1 Vault (SettlementL1 transfers from Vault free balance).
        _l2Deposit(bob, usdc, 10000e18); // also deposit on L2 for market order flow
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 2e18);

        assertEq(fills.length, 1);
        assertEq(fills[0].baseAmount, 2e18);
        assertEq(fills[0].price, 3000e18);
        assertTrue(fills[0].makerIsL1Backed);

        // Verify L1 Vault state after settlement:
        // Alice: had 5 WETH (3 locked for order). 2 unlocked & transferred to Bob. 1 still locked.
        assertEq(vault.freeBalance(alice, address(weth)), 2e18); // 5 - 3 locked + 0 = 2 free
        assertEq(vault.lockedBalance(alice, address(weth)), 1e18); // 3 - 2 = 1 locked
        // Alice received 6000 USDC from Bob
        assertEq(vault.freeBalance(alice, address(usdc)), 6000e18);

        // Bob: paid 6000 USDC, received 2 WETH in Vault
        assertEq(vault.freeBalance(bob, address(usdc)), 4000e18); // 10000 - 6000
        assertEq(vault.freeBalance(bob, address(weth)), 2e18);

        // Verify L2 caches updated
        assertEq(margin.l1FreeCache(address(weth), alice), 2e18);
        assertEq(margin.l1LockedCache(address(weth), alice), 1e18);

        // Verify trade record
        (uint256 tradeId,,,,,, bool crossChain,) = settlement.trades(1);
        assertEq(tradeId, 1);
        assertTrue(crossChain);

        // Verify order partially filled
        OrderLib.Order memory o = book.getOrder(1);
        assertEq(o.quantity, 1e18);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.PARTIALLY_FILLED));
    }

    // ========================================
    // Test 3: Cancel L1-backed order → L1 collateral released
    // ========================================
    function test_cancelL1BackedOrder() public {
        _vaultDeposit(alice, weth, 5e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));

        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(
            OrderLib.Side.SELL, 3000e18, 3e18, true
        );

        // Verify locked
        assertEq(vault.lockedBalance(alice, address(weth)), 3e18);
        assertEq(vault.freeBalance(alice, address(weth)), 2e18);

        // Cancel
        vm.prank(alice);
        engine.cancelOrder(orderId);

        // Verify unlocked on L1
        assertEq(vault.lockedBalance(alice, address(weth)), 0);
        assertEq(vault.freeBalance(alice, address(weth)), 5e18);

        // Verify cache updated
        assertEq(margin.l1FreeCache(address(weth), alice), 5e18);
        assertEq(margin.l1LockedCache(address(weth), alice), 0);

        // Verify order cancelled
        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.CANCELLED));
    }

    // ========================================
    // Test 4: Partial fills across multiple takers
    // ========================================
    function test_partialFillsCrossChain() public {
        // Alice sells 5 WETH at 3000, L1-backed
        _vaultDeposit(alice, weth, 5e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 5e18, true);

        // Bob buys 2 WETH
        _vaultDeposit(bob, usdc, 20000e18);
        vm.prank(bob);
        engine.placeMarketOrder(OrderLib.Side.BUY, 2e18);

        // Verify partial state
        assertEq(vault.lockedBalance(alice, address(weth)), 3e18); // 5-2 = 3 locked
        assertEq(vault.freeBalance(bob, address(weth)), 2e18);

        // Charlie buys 3 WETH
        address charlie = makeAddr("charlie");
        _vaultDeposit(charlie, usdc, 20000e18);
        vm.prank(charlie);
        engine.placeMarketOrder(OrderLib.Side.BUY, 3e18);

        // Alice fully filled
        assertEq(vault.lockedBalance(alice, address(weth)), 0);
        assertEq(vault.freeBalance(alice, address(usdc)), 15000e18); // 5 * 3000

        // Charlie got 3 WETH
        assertEq(vault.freeBalance(charlie, address(weth)), 3e18);
        assertEq(vault.freeBalance(charlie, address(usdc)), 11000e18); // 20000 - 9000

        // Order fully filled on book
        OrderLib.Order memory o = book.getOrder(1);
        assertEq(o.quantity, 0);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.FILLED));
    }

    // ========================================
    // Test 5: Insufficient L1 balance → order rejected
    // ========================================
    function test_insufficientL1Margin() public {
        // Alice deposits only 1 WETH to L1
        _vaultDeposit(alice, weth, 1e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));

        // Try to place order for 5 WETH — should fail
        vm.prank(alice);
        vm.expectRevert("SettlementL2: insufficient L1 balance to lock");
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 5e18, true);
    }

    // ========================================
    // Test 6: Mixed L1 and L2 orders on same book
    // ========================================
    function test_mixedL1L2Orders() public {
        // Alice: L1-backed sell at 3000
        _vaultDeposit(alice, weth, 3e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, true);

        // Charlie: L2-native sell at 3100
        address charlie = makeAddr("charlie");
        _l2Deposit(charlie, weth, 2e18);
        vm.prank(charlie);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3100e18, 2e18, false);

        // Bob buys 4 WETH — fills 3 from Alice (L1, cheaper) + 1 from Charlie (L2)
        _vaultDeposit(bob, usdc, 20000e18); // L1 for cross-chain fills
        _l2Deposit(bob, usdc, 20000e18);     // L2 for local fills
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 4e18);

        assertEq(fills.length, 2);

        // First fill: Alice's L1-backed at 3000
        assertEq(fills[0].maker, alice);
        assertEq(fills[0].baseAmount, 3e18);
        assertEq(fills[0].price, 3000e18);
        assertTrue(fills[0].makerIsL1Backed);

        // Second fill: Charlie's L2-native at 3100
        assertEq(fills[1].maker, charlie);
        assertEq(fills[1].baseAmount, 1e18);
        assertEq(fills[1].price, 3100e18);
        assertFalse(fills[1].makerIsL1Backed);

        // Verify L1: Alice got USDC, Bob got WETH
        assertEq(vault.freeBalance(alice, address(usdc)), 9000e18); // 3 * 3000
        assertEq(vault.freeBalance(bob, address(weth)), 3e18);

        // Verify L2: Charlie got USDC from Bob's L2 balance
        assertEq(margin.freeBalanceL2(charlie, address(usdc)), 3100e18); // 1 * 3100
    }

    // ========================================
    // Test 7: L1 cache refresh after deposit
    // ========================================
    function test_l1CacheRefresh() public {
        // Alice deposits 5 WETH
        _vaultDeposit(alice, weth, 5e18);

        // Cache not yet populated
        assertEq(margin.l1FreeCache(address(weth), alice), 0);

        // Verify updates cache
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        assertEq(margin.l1FreeCache(address(weth), alice), 5e18);

        // Alice deposits more on L1 (cache stale)
        _vaultDeposit(alice, weth, 3e18);
        assertEq(margin.l1FreeCache(address(weth), alice), 5e18); // still stale

        // Refresh
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        assertEq(margin.l1FreeCache(address(weth), alice), 8e18); // updated
    }

    // ========================================
    // Test 8: Cross-chain settlement reverts atomically
    // ========================================
    function test_crossChainSettlement_reverts_if_taker_no_l1_balance() public {
        // Alice: L1-backed sell at 3000
        _vaultDeposit(alice, weth, 3e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, true);

        // Bob has NO L1 USDC — cross-chain settlement should fail
        // Bob only has L2 USDC
        _l2Deposit(bob, usdc, 20000e18);
        vm.prank(bob);
        vm.expectRevert("SettlementL2: cross-chain settlement failed");
        engine.placeMarketOrder(OrderLib.Side.BUY, 2e18);

        // Verify nothing changed — atomic revert
        assertEq(vault.lockedBalance(alice, address(weth)), 3e18); // still locked
        assertEq(vault.freeBalance(alice, address(weth)), 0);
        OrderLib.Order memory o = book.getOrder(1);
        assertEq(o.quantity, 3e18); // unfilled
    }

    // ========================================
    // Test 9: Cancel partially filled L1-backed order
    // ========================================
    function test_cancelPartiallyFilledL1Order() public {
        // Alice sells 5 WETH at 3000, L1-backed
        _vaultDeposit(alice, weth, 5e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(
            OrderLib.Side.SELL, 3000e18, 5e18, true
        );

        // Bob buys 2 (partial fill)
        _vaultDeposit(bob, usdc, 10000e18);
        vm.prank(bob);
        engine.placeMarketOrder(OrderLib.Side.BUY, 2e18);

        // Alice cancels remaining 3
        vm.prank(alice);
        engine.cancelOrder(orderId);

        // All 3 remaining unlocked on L1
        assertEq(vault.lockedBalance(alice, address(weth)), 0);
        // Alice has: 5 original - 2 sold = 3 free WETH + 6000 USDC from fill
        assertEq(vault.freeBalance(alice, address(weth)), 3e18);
        assertEq(vault.freeBalance(alice, address(usdc)), 6000e18);
    }

    // ========================================
    // Test 10: L1-backed BUY order resting (no immediate match)
    // ========================================
    function test_l1BackedBuyOrder_resting() public {
        // Bob places L1-backed BUY order at 3000 — no sellers yet, so it rests
        _vaultDeposit(bob, usdc, 10000e18);
        vm.prank(bob);
        margin.verifyAndUpdateL1Balance(bob, address(usdc));

        vm.prank(bob);
        (uint256 orderId,) = engine.placeLimitOrder(
            OrderLib.Side.BUY, 3000e18, 2e18, true
        );

        // Verify L1 lock: 2 * 3000 = 6000 USDC locked
        assertEq(vault.lockedBalance(bob, address(usdc)), 6000e18);
        assertEq(vault.freeBalance(bob, address(usdc)), 4000e18);

        // Order rests on book
        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(o.quantity, 2e18);
        assertTrue(o.isL1Backed);
        assertEq(uint8(o.side), uint8(OrderLib.Side.BUY));

        // Alice sells against Bob's L1-backed BUY (cross-chain path because maker=Bob is L1-backed)
        _vaultDeposit(alice, weth, 3e18);
        vm.prank(alice);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.SELL, 2e18);

        assertEq(fills.length, 1);
        assertEq(fills[0].maker, bob);
        assertTrue(fills[0].makerIsL1Backed);

        // L1 Vault: Bob unlocked USDC transferred to Alice, Alice's WETH to Bob
        assertEq(vault.freeBalance(alice, address(usdc)), 6000e18);
        assertEq(vault.freeBalance(bob, address(weth)), 2e18);
        assertEq(vault.lockedBalance(bob, address(usdc)), 0);
    }

    // ========================================
    // Test 11: Verify L1 settlement atomically reverts for multiple fills
    // ========================================
    function test_multipleL1BackedMakers() public {
        // Two L1-backed makers at different prices
        address charlie = makeAddr("charlie");

        _vaultDeposit(alice, weth, 3e18);
        vm.prank(alice);
        margin.verifyAndUpdateL1Balance(alice, address(weth));
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, true);

        _vaultDeposit(charlie, weth, 2e18);
        vm.prank(charlie);
        margin.verifyAndUpdateL1Balance(charlie, address(weth));
        vm.prank(charlie);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3100e18, 2e18, true);

        // Bob buys 4 WETH — fills from both L1-backed makers
        _vaultDeposit(bob, usdc, 30000e18);
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 4e18);

        assertEq(fills.length, 2);

        // Alice filled 3 at 3000 = 9000 USDC
        assertEq(vault.freeBalance(alice, address(usdc)), 9000e18);
        assertEq(vault.lockedBalance(alice, address(weth)), 0);

        // Charlie filled 1 at 3100 = 3100 USDC
        assertEq(vault.freeBalance(charlie, address(usdc)), 3100e18);
        assertEq(vault.lockedBalance(charlie, address(weth)), 1e18); // 1 still locked

        // Bob spent 9000 + 3100 = 12100, got 4 WETH
        assertEq(vault.freeBalance(bob, address(weth)), 4e18);
        assertEq(vault.freeBalance(bob, address(usdc)), 17900e18); // 30000 - 12100
    }
}
