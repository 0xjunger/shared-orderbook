// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISettlementL2 {
    function settleLocal(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external returns (uint256 tradeId);

    function settleCrossChain(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external returns (uint256 tradeId);

    function releaseCrossChain(
        address user,
        address token,
        uint256 amount
    ) external;

    function lockCrossChain(
        address user,
        address token,
        uint256 amount
    ) external returns (bool success);
}
