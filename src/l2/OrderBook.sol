// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {OrderLib} from "../libraries/OrderLib.sol";

contract OrderBook is IOrderBook {
    using OrderLib for *;

    uint256 public nextOrderId = 1;
    address public matchingEngine;
    address public owner;

    // orderId => Order
    mapping(uint256 => OrderLib.Order) internal _orders;

    // side => price => ordered list of order IDs
    mapping(OrderLib.Side => mapping(uint256 => uint256[])) internal _levels;

    // sorted price arrays
    uint256[] internal _buyPrices;   // sorted descending (best bid first)
    uint256[] internal _sellPrices;  // sorted ascending (best ask first)

    // trader => orderId[]
    mapping(address => uint256[]) internal _userOrders;

    modifier onlyMatchingEngine() {
        require(msg.sender == matchingEngine, "OrderBook: not matching engine");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "OrderBook: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setMatchingEngine(address _engine) external onlyOwner {
        matchingEngine = _engine;
    }

    function insertOrder(
        address trader,
        OrderLib.Side side,
        OrderLib.OrderType orderType,
        uint256 price,
        uint256 quantity,
        bool isL1Backed
    ) external override onlyMatchingEngine returns (uint256 orderId) {
        orderId = nextOrderId++;
        _orders[orderId] = OrderLib.Order({
            orderId: orderId,
            trader: trader,
            side: side,
            orderType: orderType,
            price: price,
            quantity: quantity,
            filledQuantity: 0,
            timestamp: block.timestamp,
            status: OrderLib.OrderStatus.OPEN,
            isL1Backed: isL1Backed
        });

        // Add to price level
        _levels[side][price].push(orderId);

        // Insert price into sorted array if new level
        if (_levels[side][price].length == 1) {
            _insertPrice(side, price);
        }

        _userOrders[trader].push(orderId);

        emit OrderInserted(orderId, trader, side, price, quantity);
    }

    function removeOrder(uint256 orderId) external override onlyMatchingEngine {
        OrderLib.Order storage order = _orders[orderId];
        require(order.orderId != 0, "OrderBook: order not found");

        order.status = OrderLib.OrderStatus.CANCELLED;

        // Remove from price level
        _removeFromLevel(order.side, order.price, orderId);

        // Remove price level if empty
        if (_levels[order.side][order.price].length == 0) {
            _removePrice(order.side, order.price);
        }

        emit OrderRemoved(orderId);
    }

    function updateOrderFill(uint256 orderId, uint256 fillAmount) external override onlyMatchingEngine {
        OrderLib.Order storage order = _orders[orderId];
        require(order.orderId != 0, "OrderBook: order not found");

        order.filledQuantity += fillAmount;
        order.quantity -= fillAmount;

        if (order.quantity == 0) {
            order.status = OrderLib.OrderStatus.FILLED;
            _removeFromLevel(order.side, order.price, orderId);
            if (_levels[order.side][order.price].length == 0) {
                _removePrice(order.side, order.price);
            }
        } else {
            order.status = OrderLib.OrderStatus.PARTIALLY_FILLED;
        }

        emit OrderUpdated(orderId, order.quantity);
    }

    function getOrder(uint256 orderId) external view override returns (OrderLib.Order memory) {
        return _orders[orderId];
    }

    function getBestBid() external view override returns (uint256 price, uint256 totalQty) {
        if (_buyPrices.length == 0) return (0, 0);
        price = _buyPrices[0]; // highest buy price
        uint256[] storage ids = _levels[OrderLib.Side.BUY][price];
        for (uint256 i = 0; i < ids.length; i++) {
            totalQty += _orders[ids[i]].quantity;
        }
    }

    function getBestAsk() external view override returns (uint256 price, uint256 totalQty) {
        if (_sellPrices.length == 0) return (0, 0);
        price = _sellPrices[0]; // lowest sell price
        uint256[] storage ids = _levels[OrderLib.Side.SELL][price];
        for (uint256 i = 0; i < ids.length; i++) {
            totalQty += _orders[ids[i]].quantity;
        }
    }

    function getOrdersAtPrice(OrderLib.Side side, uint256 price) external view override returns (uint256[] memory) {
        return _levels[side][price];
    }

    function getBuyPrices() external view override returns (uint256[] memory) {
        return _buyPrices;
    }

    function getSellPrices() external view override returns (uint256[] memory) {
        return _sellPrices;
    }

    // --- Internal helpers ---

    function _insertPrice(OrderLib.Side side, uint256 price) internal {
        if (side == OrderLib.Side.BUY) {
            // Insert descending (highest first)
            uint256 len = _buyPrices.length;
            _buyPrices.push(price);
            uint256 i = len;
            while (i > 0 && _buyPrices[i - 1] < price) {
                _buyPrices[i] = _buyPrices[i - 1];
                i--;
            }
            _buyPrices[i] = price;
        } else {
            // Insert ascending (lowest first)
            uint256 len = _sellPrices.length;
            _sellPrices.push(price);
            uint256 i = len;
            while (i > 0 && _sellPrices[i - 1] > price) {
                _sellPrices[i] = _sellPrices[i - 1];
                i--;
            }
            _sellPrices[i] = price;
        }
    }

    function _removePrice(OrderLib.Side side, uint256 price) internal {
        uint256[] storage prices = side == OrderLib.Side.BUY ? _buyPrices : _sellPrices;
        uint256 len = prices.length;
        for (uint256 i = 0; i < len; i++) {
            if (prices[i] == price) {
                prices[i] = prices[len - 1];
                prices.pop();
                // Re-sort after swap (insertion sort the swapped element)
                if (i < prices.length) {
                    _resortAfterSwap(side, prices, i);
                }
                return;
            }
        }
    }

    function _resortAfterSwap(OrderLib.Side side, uint256[] storage prices, uint256 idx) internal {
        uint256 val = prices[idx];
        if (side == OrderLib.Side.BUY) {
            // Descending: move left if val is larger, right if smaller
            while (idx > 0 && prices[idx - 1] < val) {
                prices[idx] = prices[idx - 1];
                idx--;
            }
            while (idx < prices.length - 1 && prices[idx + 1] > val) {
                prices[idx] = prices[idx + 1];
                idx++;
            }
        } else {
            // Ascending: move left if val is smaller, right if larger
            while (idx > 0 && prices[idx - 1] > val) {
                prices[idx] = prices[idx - 1];
                idx--;
            }
            while (idx < prices.length - 1 && prices[idx + 1] < val) {
                prices[idx] = prices[idx + 1];
                idx++;
            }
        }
        prices[idx] = val;
    }

    function _removeFromLevel(OrderLib.Side side, uint256 price, uint256 orderId) internal {
        uint256[] storage ids = _levels[side][price];
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            if (ids[i] == orderId) {
                ids[i] = ids[len - 1];
                ids.pop();
                return;
            }
        }
    }

    event OrderInserted(uint256 indexed orderId, address indexed trader, OrderLib.Side side, uint256 price, uint256 quantity);
    event OrderRemoved(uint256 indexed orderId);
    event OrderUpdated(uint256 indexed orderId, uint256 remainingQuantity);
}
