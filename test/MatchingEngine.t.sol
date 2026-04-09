// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
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

contract MatchingEngineTest is Test {
    OrderBook book;
    MatchingEngine engine;
    MarginL2 margin;
    SettlementL2 settlement;
    MockERC20 baseToken;  // WETH
    MockERC20 quoteToken; // USDC

    address alice = makeAddr("alice"); // maker
    address bob = makeAddr("bob");     // taker

    function setUp() public {
        baseToken = new MockERC20("Wrapped Ether", "WETH");
        quoteToken = new MockERC20("USD Coin", "USDC");

        book = new OrderBook();
        margin = new MarginL2();
        settlement = new SettlementL2(address(margin));

        engine = new MatchingEngine(
            address(book),
            address(settlement),
            address(margin),
            address(baseToken),
            address(quoteToken)
        );

        // Wire permissions
        book.setMatchingEngine(address(engine));
        margin.setMatchingEngine(address(engine));
        margin.setSettlement(address(settlement));
        settlement.setMatchingEngine(address(engine));
    }

    function _depositBase(address user, uint256 amount) internal {
        baseToken.mint(user, amount);
        vm.startPrank(user);
        baseToken.approve(address(margin), amount);
        margin.depositL2(address(baseToken), amount);
        vm.stopPrank();
    }

    function _depositQuote(address user, uint256 amount) internal {
        quoteToken.mint(user, amount);
        vm.startPrank(user);
        quoteToken.approve(address(margin), amount);
        margin.depositL2(address(quoteToken), amount);
        vm.stopPrank();
    }

    // --- Limit Order Placement ---

    function test_placeLimitOrder_sell() public {
        _depositBase(alice, 5e18);

        vm.prank(alice);
        (uint256 orderId, OrderLib.Fill[] memory fills) = engine.placeLimitOrder(
            OrderLib.Side.SELL, 3000e18, 3e18, false
        );

        assertEq(orderId, 1);
        assertEq(fills.length, 0);

        // Margin locked
        assertEq(margin.freeBalanceL2(alice, address(baseToken)), 2e18);

        // Order on book
        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(o.quantity, 3e18);
        assertEq(o.price, 3000e18);
    }

    function test_placeLimitOrder_buy() public {
        _depositQuote(alice, 10000e18);

        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(
            OrderLib.Side.BUY, 3000e18, 2e18, false
        );

        // Should lock 2 * 3000 = 6000 quote tokens
        assertEq(margin.freeBalanceL2(alice, address(quoteToken)), 4000e18);

        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(uint8(o.side), uint8(OrderLib.Side.BUY));
    }

    function test_placeLimitOrder_revert_insufficientMargin() public {
        _depositBase(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert("MatchingEngine: insufficient L2 margin");
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 5e18, false);
    }

    // --- Market Order + Matching ---

    function test_marketOrder_fullFill() public {
        // Alice sells 3 WETH at 3000
        _depositBase(alice, 3e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, false);

        // Bob buys 2 WETH market
        _depositQuote(bob, 10000e18);
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 2e18);

        assertEq(fills.length, 1);
        assertEq(fills[0].baseAmount, 2e18);
        assertEq(fills[0].price, 3000e18);

        // Alice: received 6000 USDC, gave 2 WETH (1 still locked)
        assertEq(margin.freeBalanceL2(alice, address(quoteToken)), 6000e18);

        // Bob: received 2 WETH, paid 6000 USDC
        assertEq(margin.freeBalanceL2(bob, address(baseToken)), 2e18);
        assertEq(margin.freeBalanceL2(bob, address(quoteToken)), 4000e18);

        // Maker order partially filled
        OrderLib.Order memory o = book.getOrder(1);
        assertEq(o.quantity, 1e18);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.PARTIALLY_FILLED));
    }

    function test_marketOrder_revert_insufficientLiquidity() public {
        _depositBase(alice, 1e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 1e18, false);

        _depositQuote(bob, 20000e18);
        vm.prank(bob);
        vm.expectRevert("MatchingEngine: insufficient liquidity");
        engine.placeMarketOrder(OrderLib.Side.BUY, 5e18);
    }

    // --- Price Priority ---

    function test_marketOrder_fillsCheapestFirst() public {
        address charlie = makeAddr("charlie");

        // Alice sells 1 WETH at 3100
        _depositBase(alice, 1e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3100e18, 1e18, false);

        // Charlie sells 1 WETH at 3000 (cheaper)
        _depositBase(charlie, 1e18);
        vm.prank(charlie);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 1e18, false);

        // Bob buys 1 WETH — should fill at 3000 (charlie's order)
        _depositQuote(bob, 10000e18);
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 1e18);

        assertEq(fills.length, 1);
        assertEq(fills[0].price, 3000e18);
        assertEq(fills[0].maker, charlie);
    }

    // --- Multiple Fills ---

    function test_marketOrder_multipleFills() public {
        address charlie = makeAddr("charlie");

        _depositBase(alice, 2e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 2e18, false);

        _depositBase(charlie, 3e18);
        vm.prank(charlie);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3100e18, 3e18, false);

        // Bob buys 4 WETH — fills 2 at 3000 + 2 at 3100
        _depositQuote(bob, 20000e18);
        vm.prank(bob);
        OrderLib.Fill[] memory fills = engine.placeMarketOrder(OrderLib.Side.BUY, 4e18);

        assertEq(fills.length, 2);
        assertEq(fills[0].baseAmount, 2e18);
        assertEq(fills[0].price, 3000e18);
        assertEq(fills[1].baseAmount, 2e18);
        assertEq(fills[1].price, 3100e18);
    }

    // --- Cancel ---

    function test_cancelOrder() public {
        _depositBase(alice, 5e18);
        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, false);

        assertEq(margin.freeBalanceL2(alice, address(baseToken)), 2e18);

        vm.prank(alice);
        engine.cancelOrder(orderId);

        // Margin released
        assertEq(margin.freeBalanceL2(alice, address(baseToken)), 5e18);

        // Order cancelled
        OrderLib.Order memory o = book.getOrder(orderId);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.CANCELLED));
    }

    function test_cancelOrder_revert_notOwner() public {
        _depositBase(alice, 5e18);
        vm.prank(alice);
        (uint256 orderId,) = engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, false);

        vm.prank(bob);
        vm.expectRevert("MatchingEngine: not order owner");
        engine.cancelOrder(orderId);
    }

    // --- Limit Order Crossing ---

    function test_limitOrder_immediateMatch() public {
        // Alice has sell at 3000
        _depositBase(alice, 3e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, false);

        // Bob places buy limit at 3000 — crosses the spread
        _depositQuote(bob, 10000e18);
        vm.prank(bob);
        (uint256 orderId, OrderLib.Fill[] memory fills) = engine.placeLimitOrder(
            OrderLib.Side.BUY, 3000e18, 2e18, false
        );

        assertEq(fills.length, 1);
        assertEq(fills[0].baseAmount, 2e18);
        // No resting order since fully filled
        assertEq(orderId, 0);
    }

    function test_limitOrder_partialMatchAndRest() public {
        _depositBase(alice, 1e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 1e18, false);

        _depositQuote(bob, 15000e18);
        vm.prank(bob);
        (uint256 orderId, OrderLib.Fill[] memory fills) = engine.placeLimitOrder(
            OrderLib.Side.BUY, 3000e18, 3e18, false
        );

        // 1 fill, 2 remaining rests on book
        assertEq(fills.length, 1);
        assertGt(orderId, 0);

        OrderLib.Order memory resting = book.getOrder(orderId);
        assertEq(resting.quantity, 2e18);
        assertEq(uint8(resting.side), uint8(OrderLib.Side.BUY));
    }

    // --- Trade Record ---

    function test_tradeRecord() public {
        _depositBase(alice, 3e18);
        vm.prank(alice);
        engine.placeLimitOrder(OrderLib.Side.SELL, 3000e18, 3e18, false);

        _depositQuote(bob, 10000e18);
        vm.prank(bob);
        engine.placeMarketOrder(OrderLib.Side.BUY, 1e18);

        (uint256 tradeId,,,,,, bool crossChain,) = settlement.trades(1);
        assertEq(tradeId, 1);
        assertFalse(crossChain);
    }
}
