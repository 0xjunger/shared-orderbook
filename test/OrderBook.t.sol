// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {OrderBook} from "../src/l2/OrderBook.sol";
import {OrderLib} from "../src/libraries/OrderLib.sol";

contract OrderBookTest is Test {
    OrderBook book;
    address engine = makeAddr("engine");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        book = new OrderBook();
        book.setMatchingEngine(engine);
    }

    function test_insertBuyOrder() public {
        vm.prank(engine);
        uint256 id = book.insertOrder(alice, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 3000e18, 1e18, false);
        assertEq(id, 1);

        OrderLib.Order memory o = book.getOrder(id);
        assertEq(o.trader, alice);
        assertEq(o.price, 3000e18);
        assertEq(o.quantity, 1e18);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.OPEN));
    }

    function test_insertSellOrder() public {
        vm.prank(engine);
        uint256 id = book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3100e18, 2e18, true);

        OrderLib.Order memory o = book.getOrder(id);
        assertTrue(o.isL1Backed);
        assertEq(o.quantity, 2e18);
    }

    function test_priceTimePriority_buy() public {
        // Insert buy orders at different prices
        vm.startPrank(engine);
        book.insertOrder(alice, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 2900e18, 1e18, false);
        book.insertOrder(bob, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 3000e18, 2e18, false);
        book.insertOrder(alice, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 2950e18, 1e18, false);
        vm.stopPrank();

        // Best bid should be highest price
        (uint256 bestPrice,) = book.getBestBid();
        assertEq(bestPrice, 3000e18);

        uint256[] memory prices = book.getBuyPrices();
        assertEq(prices.length, 3);
        assertEq(prices[0], 3000e18); // highest first
        assertEq(prices[1], 2950e18);
        assertEq(prices[2], 2900e18);
    }

    function test_priceTimePriority_sell() public {
        vm.startPrank(engine);
        book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3100e18, 1e18, false);
        book.insertOrder(bob, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 2e18, false);
        book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3050e18, 1e18, false);
        vm.stopPrank();

        // Best ask should be lowest price
        (uint256 bestPrice,) = book.getBestAsk();
        assertEq(bestPrice, 3000e18);

        uint256[] memory prices = book.getSellPrices();
        assertEq(prices.length, 3);
        assertEq(prices[0], 3000e18); // lowest first
        assertEq(prices[1], 3050e18);
        assertEq(prices[2], 3100e18);
    }

    function test_removeOrder() public {
        vm.startPrank(engine);
        uint256 id1 = book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 1e18, false);
        book.insertOrder(bob, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 2e18, false);

        book.removeOrder(id1);
        vm.stopPrank();

        OrderLib.Order memory o = book.getOrder(id1);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.CANCELLED));

        // Price level still exists (bob's order remains)
        uint256[] memory ids = book.getOrdersAtPrice(OrderLib.Side.SELL, 3000e18);
        assertEq(ids.length, 1);
    }

    function test_removeLastAtPrice_removesLevel() public {
        vm.startPrank(engine);
        uint256 id1 = book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 1e18, false);
        book.removeOrder(id1);
        vm.stopPrank();

        uint256[] memory prices = book.getSellPrices();
        assertEq(prices.length, 0);
    }

    function test_updateOrderFill_partial() public {
        vm.startPrank(engine);
        uint256 id = book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 5e18, false);
        book.updateOrderFill(id, 2e18);
        vm.stopPrank();

        OrderLib.Order memory o = book.getOrder(id);
        assertEq(o.quantity, 3e18);
        assertEq(o.filledQuantity, 2e18);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.PARTIALLY_FILLED));
    }

    function test_updateOrderFill_full() public {
        vm.startPrank(engine);
        uint256 id = book.insertOrder(alice, OrderLib.Side.SELL, OrderLib.OrderType.LIMIT, 3000e18, 5e18, false);
        book.updateOrderFill(id, 5e18);
        vm.stopPrank();

        OrderLib.Order memory o = book.getOrder(id);
        assertEq(o.quantity, 0);
        assertEq(uint8(o.status), uint8(OrderLib.OrderStatus.FILLED));

        // Price level removed
        uint256[] memory prices = book.getSellPrices();
        assertEq(prices.length, 0);
    }

    function test_revert_notMatchingEngine() public {
        vm.prank(alice);
        vm.expectRevert("OrderBook: not matching engine");
        book.insertOrder(alice, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 3000e18, 1e18, false);
    }

    function test_multipleOrdersSamePrice() public {
        vm.startPrank(engine);
        uint256 id1 = book.insertOrder(alice, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 3000e18, 1e18, false);
        uint256 id2 = book.insertOrder(bob, OrderLib.Side.BUY, OrderLib.OrderType.LIMIT, 3000e18, 2e18, false);
        vm.stopPrank();

        (uint256 price, uint256 totalQty) = book.getBestBid();
        assertEq(price, 3000e18);
        assertEq(totalQty, 3e18);

        uint256[] memory ids = book.getOrdersAtPrice(OrderLib.Side.BUY, 3000e18);
        assertEq(ids.length, 2);
        assertEq(ids[0], id1);
        assertEq(ids[1], id2);
    }
}
