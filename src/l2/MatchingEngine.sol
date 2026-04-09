// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMatchingEngine} from "../interfaces/IMatchingEngine.sol";
import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {IMarginL2} from "../interfaces/IMarginL2.sol";
import {ISettlementL2} from "../interfaces/ISettlementL2.sol";
import {OrderLib} from "../libraries/OrderLib.sol";

contract MatchingEngine is IMatchingEngine {
    IOrderBook public orderBook;
    ISettlementL2 public settlement;
    IMarginL2 public margin;

    address public baseToken;
    address public quoteToken;
    address public owner;

    uint256 public constant MAX_FILLS_PER_TX = 20;

    modifier onlyOwner() {
        require(msg.sender == owner, "MatchingEngine: not owner");
        _;
    }

    constructor(
        address _orderBook,
        address _settlement,
        address _margin,
        address _baseToken,
        address _quoteToken
    ) {
        orderBook = IOrderBook(_orderBook);
        settlement = ISettlementL2(_settlement);
        margin = IMarginL2(_margin);
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        owner = msg.sender;
    }

    /// @notice Place a limit order. Crosses the spread if possible, remaining rests.
    function placeLimitOrder(
        OrderLib.Side side,
        uint256 price,
        uint256 quantity,
        bool useL1Collateral
    ) external override returns (uint256 orderId, OrderLib.Fill[] memory fills) {
        require(quantity > 0, "MatchingEngine: zero quantity");
        require(price > 0, "MatchingEngine: zero price");

        // Check margin for the order
        _checkAndLockMargin(msg.sender, side, price, quantity, useL1Collateral);

        // Try to match against opposite side. takerLocked=true so fills unlock before transfer.
        uint256 remaining;
        (fills, remaining) = _matchOrder(msg.sender, side, price, quantity, !useL1Collateral);

        // Rest remaining quantity on the book
        if (remaining > 0) {
            orderId = orderBook.insertOrder(
                msg.sender, side, OrderLib.OrderType.LIMIT,
                price, remaining, useL1Collateral
            );
        }

        emit OrderPlaced(msg.sender, orderId, side, price, quantity, fills.length);
    }

    /// @notice Place a market order. Must fill entirely or revert.
    function placeMarketOrder(
        OrderLib.Side side,
        uint256 quantity
    ) external override returns (OrderLib.Fill[] memory fills) {
        require(quantity > 0, "MatchingEngine: zero quantity");

        // For market orders, we don't lock margin upfront — settle immediately
        uint256 remaining;
        (fills, remaining) = _matchOrder(msg.sender, side, 0, quantity, false);
        require(remaining == 0, "MatchingEngine: insufficient liquidity");

        emit MarketOrderFilled(msg.sender, side, quantity, fills.length);
    }

    /// @notice Cancel an open order and release locked margin.
    function cancelOrder(uint256 orderId) external override {
        OrderLib.Order memory order = orderBook.getOrder(orderId);
        require(order.orderId != 0, "MatchingEngine: order not found");
        require(order.trader == msg.sender, "MatchingEngine: not order owner");
        require(
            order.status == OrderLib.OrderStatus.OPEN ||
            order.status == OrderLib.OrderStatus.PARTIALLY_FILLED,
            "MatchingEngine: order not cancellable"
        );

        // Release margin
        if (order.isL1Backed) {
            // Cross-chain release (Phase 2)
            (address token, uint256 amount) = _orderCollateral(order);
            settlement.releaseCrossChain(msg.sender, token, amount);
        } else {
            (address token, uint256 amount) = _orderCollateral(order);
            margin.unlockL2(msg.sender, token, amount);
        }

        orderBook.removeOrder(orderId);
        emit OrderCancelled(orderId, msg.sender);
    }

    // --- Internal ---

    function _matchOrder(
        address taker,
        OrderLib.Side takerSide,
        uint256 limitPrice, // 0 = market (accept any price)
        uint256 quantity,
        bool takerLocked    // true if taker pre-locked margin (limit orders)
    ) internal returns (OrderLib.Fill[] memory fills, uint256 remaining) {
        remaining = quantity;

        // Temporary array for fills (max bounded)
        OrderLib.Fill[] memory tempFills = new OrderLib.Fill[](MAX_FILLS_PER_TX);
        uint256 fillCount = 0;

        // Get opposite side prices
        OrderLib.Side makerSide = takerSide == OrderLib.Side.BUY
            ? OrderLib.Side.SELL
            : OrderLib.Side.BUY;

        uint256[] memory prices = makerSide == OrderLib.Side.SELL
            ? orderBook.getSellPrices()
            : orderBook.getBuyPrices();

        for (uint256 p = 0; p < prices.length && remaining > 0 && fillCount < MAX_FILLS_PER_TX; p++) {
            uint256 makerPrice = prices[p];

            // Price check for limit orders
            if (limitPrice > 0) {
                if (takerSide == OrderLib.Side.BUY && makerPrice > limitPrice) break;
                if (takerSide == OrderLib.Side.SELL && makerPrice < limitPrice) break;
            }

            uint256[] memory orderIds = orderBook.getOrdersAtPrice(makerSide, makerPrice);

            for (uint256 i = 0; i < orderIds.length && remaining > 0 && fillCount < MAX_FILLS_PER_TX; i++) {
                OrderLib.Order memory makerOrder = orderBook.getOrder(orderIds[i]);
                if (makerOrder.status != OrderLib.OrderStatus.OPEN &&
                    makerOrder.status != OrderLib.OrderStatus.PARTIALLY_FILLED) {
                    continue;
                }

                uint256 fillQty = remaining < makerOrder.quantity ? remaining : makerOrder.quantity;
                uint256 fillQuote = fillQty * makerPrice / 1e18;

                // If taker pre-locked margin (limit order), unlock before settlement
                if (takerLocked) {
                    (address tkrToken, uint256 tkrAmt) = _requiredCollateral(takerSide, makerPrice, fillQty);
                    margin.unlockL2(taker, tkrToken, tkrAmt);
                }

                // Settle the fill
                _settleFill(
                    makerOrder.trader,
                    taker,
                    makerPrice,
                    fillQty,
                    fillQuote,
                    makerOrder.side == OrderLib.Side.BUY,
                    makerOrder.isL1Backed
                );

                // Update the maker order on the book
                orderBook.updateOrderFill(makerOrder.orderId, fillQty);

                tempFills[fillCount] = OrderLib.Fill({
                    makerOrderId: makerOrder.orderId,
                    maker: makerOrder.trader,
                    taker: taker,
                    price: makerPrice,
                    baseAmount: fillQty,
                    quoteAmount: fillQuote,
                    makerIsL1Backed: makerOrder.isL1Backed
                });

                fillCount++;
                remaining -= fillQty;
            }
        }

        // Copy to correctly-sized array
        fills = new OrderLib.Fill[](fillCount);
        for (uint256 i = 0; i < fillCount; i++) {
            fills[i] = tempFills[i];
        }
    }

    function _settleFill(
        address maker,
        address taker,
        uint256 price,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy,
        bool makerIsL1Backed
    ) internal {
        if (makerIsL1Backed) {
            settlement.settleCrossChain(
                maker, taker, baseToken, quoteToken,
                baseAmount, quoteAmount, makerIsBuy
            );
        } else {
            settlement.settleLocal(
                maker, taker, baseToken, quoteToken,
                baseAmount, quoteAmount, makerIsBuy
            );
        }
    }

    function _checkAndLockMargin(
        address trader,
        OrderLib.Side side,
        uint256 price,
        uint256 quantity,
        bool useL1Collateral
    ) internal {
        (address token, uint256 required) = _requiredCollateral(side, price, quantity);

        if (useL1Collateral) {
            // Lock on L1 Vault via cross-chain call through SettlementL2
            settlement.lockCrossChain(trader, token, required);
        } else {
            require(
                margin.checkMargin(trader, token, required, false),
                "MatchingEngine: insufficient L2 margin"
            );
            margin.lockL2(trader, token, required);
        }
    }

    function _requiredCollateral(
        OrderLib.Side side,
        uint256 price,
        uint256 quantity
    ) internal view returns (address token, uint256 amount) {
        if (side == OrderLib.Side.SELL) {
            // Selling base token: need base token as collateral
            token = baseToken;
            amount = quantity;
        } else {
            // Buying base token: need quote token as collateral
            token = quoteToken;
            amount = quantity * price / 1e18;
        }
    }

    function _orderCollateral(OrderLib.Order memory order) internal view returns (address token, uint256 amount) {
        return _requiredCollateral(order.side, order.price, order.quantity);
    }

    event OrderPlaced(address indexed trader, uint256 indexed orderId, OrderLib.Side side, uint256 price, uint256 quantity, uint256 immediateMatches);
    event OrderCancelled(uint256 indexed orderId, address indexed trader);
    event MarketOrderFilled(address indexed trader, OrderLib.Side side, uint256 quantity, uint256 fillCount);
}
