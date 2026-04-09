// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library OrderLib {
    enum Side { BUY, SELL }
    enum OrderType { LIMIT, MARKET }
    enum OrderStatus { OPEN, PARTIALLY_FILLED, FILLED, CANCELLED }

    struct Order {
        uint256 orderId;
        address trader;
        Side side;
        OrderType orderType;
        uint256 price;          // in quote token decimals
        uint256 quantity;       // remaining quantity in base token decimals
        uint256 filledQuantity;
        uint256 timestamp;
        OrderStatus status;
        bool isL1Backed;
    }

    struct Fill {
        uint256 makerOrderId;
        address maker;
        address taker;
        uint256 price;
        uint256 baseAmount;
        uint256 quoteAmount;
        bool makerIsL1Backed;
    }
}
