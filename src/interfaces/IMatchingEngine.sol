// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderLib} from "../libraries/OrderLib.sol";

interface IMatchingEngine {
    function placeLimitOrder(
        OrderLib.Side side,
        uint256 price,
        uint256 quantity,
        bool useL1Collateral
    ) external returns (uint256 orderId, OrderLib.Fill[] memory fills);

    function placeMarketOrder(
        OrderLib.Side side,
        uint256 quantity
    ) external returns (OrderLib.Fill[] memory fills);

    function cancelOrder(uint256 orderId) external;
}
