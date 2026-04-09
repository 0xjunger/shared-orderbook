// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISettlementL1 {
    function settleTrade(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external returns (bool);

    function lockForOrder(
        address user,
        address token,
        uint256 amount
    ) external returns (bool success, uint256 freeAfter);

    function releaseOnCancel(
        address user,
        address token,
        uint256 amount
    ) external returns (bool);

    function getAvailableBalance(
        address user,
        address token
    ) external view returns (uint256 free, uint256 locked);
}
