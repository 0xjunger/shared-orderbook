// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderLib} from "../libraries/OrderLib.sol";

interface IOrderBook {
    function insertOrder(
        address trader,
        OrderLib.Side side,
        OrderLib.OrderType orderType,
        uint256 price,
        uint256 quantity,
        bool isL1Backed
    ) external returns (uint256 orderId);

    function removeOrder(uint256 orderId) external;
    function updateOrderFill(uint256 orderId, uint256 fillAmount) external;
    function getOrder(uint256 orderId) external view returns (OrderLib.Order memory);
    function getBestBid() external view returns (uint256 price, uint256 totalQty);
    function getBestAsk() external view returns (uint256 price, uint256 totalQty);
    function getOrdersAtPrice(OrderLib.Side side, uint256 price) external view returns (uint256[] memory orderIds);
    function getBuyPrices() external view returns (uint256[] memory);
    function getSellPrices() external view returns (uint256[] memory);
}
