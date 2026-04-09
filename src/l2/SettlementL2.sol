// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISettlementL2} from "../interfaces/ISettlementL2.sol";
import {IMarginL2} from "../interfaces/IMarginL2.sol";
import {ISettlementL1} from "../interfaces/ISettlementL1.sol";

contract SettlementL2 is ISettlementL2 {
    IMarginL2 public margin;
    address public matchingEngine;
    address public owner;

    // Cross-chain proxy address of SettlementL1 on L2 (set in Phase 2)
    address public settlementL1Proxy;

    uint256 public nextTradeId = 1;

    struct TradeRecord {
        uint256 tradeId;
        address maker;
        address taker;
        uint256 price;
        uint256 baseAmount;
        uint256 quoteAmount;
        bool crossChain;
        uint256 timestamp;
    }

    mapping(uint256 => TradeRecord) public trades;

    modifier onlyMatchingEngine() {
        require(msg.sender == matchingEngine, "SettlementL2: not matching engine");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SettlementL2: not owner");
        _;
    }

    constructor(address _margin) {
        margin = IMarginL2(_margin);
        owner = msg.sender;
    }

    function setMatchingEngine(address _engine) external onlyOwner {
        matchingEngine = _engine;
    }

    function setSettlementL1Proxy(address _proxy) external onlyOwner {
        settlementL1Proxy = _proxy;
    }

    /// @notice Settle a trade where both parties have L2 collateral.
    /// Maker's collateral was locked at order placement. Taker pays from free balance.
    function settleLocal(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external override onlyMatchingEngine returns (uint256 tradeId) {
        if (makerIsBuy) {
            // Maker buys base, sells quote. Taker sells base, buys quote.
            // Maker's locked quote -> taker
            margin.unlockL2(maker, quoteToken, quoteAmount);
            margin.transferL2(maker, taker, quoteToken, quoteAmount);
            // Taker's free base -> maker (taker never locked for market orders)
            margin.transferL2(taker, maker, baseToken, baseAmount);
        } else {
            // Maker sells base, buys quote. Taker buys base, sells quote.
            // Maker's locked base -> taker
            margin.unlockL2(maker, baseToken, baseAmount);
            margin.transferL2(maker, taker, baseToken, baseAmount);
            // Taker's free quote -> maker
            margin.transferL2(taker, maker, quoteToken, quoteAmount);
        }

        tradeId = _recordTrade(maker, taker, baseAmount, quoteAmount, false);
    }

    /// @notice Settle a cross-chain trade where maker has L1 collateral.
    /// Calls SettlementL1 via cross-chain proxy, then updates L1 caches.
    function settleCrossChain(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external override onlyMatchingEngine returns (uint256 tradeId) {
        require(settlementL1Proxy != address(0), "SettlementL2: cross-chain not configured");

        // Call SettlementL1 via cross-chain proxy
        (bool ok, bytes memory ret) = settlementL1Proxy.call(
            abi.encodeWithSelector(
                ISettlementL1.settleTrade.selector,
                maker, taker, baseToken, quoteToken,
                baseAmount, quoteAmount, makerIsBuy
            )
        );
        require(ok && abi.decode(ret, (bool)), "SettlementL2: cross-chain settlement failed");

        // Update L1 caches for both parties
        _refreshL1Cache(maker, baseToken);
        _refreshL1Cache(maker, quoteToken);
        _refreshL1Cache(taker, baseToken);
        _refreshL1Cache(taker, quoteToken);

        tradeId = _recordTrade(maker, taker, baseAmount, quoteAmount, true);
    }

    /// @notice Release L1 collateral on order cancellation.
    function releaseCrossChain(
        address user,
        address token,
        uint256 amount
    ) external override onlyMatchingEngine {
        require(settlementL1Proxy != address(0), "SettlementL2: cross-chain not configured");

        (bool ok, bytes memory ret) = settlementL1Proxy.call(
            abi.encodeWithSelector(
                ISettlementL1.releaseOnCancel.selector,
                user, token, amount
            )
        );
        require(ok && abi.decode(ret, (bool)), "SettlementL2: cross-chain release failed");

        // Update L1 cache after release
        _refreshL1Cache(user, token);
    }

    /// @notice Lock L1 collateral for a new order via cross-chain call.
    function lockCrossChain(
        address user,
        address token,
        uint256 amount
    ) external onlyMatchingEngine returns (bool success) {
        require(settlementL1Proxy != address(0), "SettlementL2: cross-chain not configured");

        (bool ok, bytes memory ret) = settlementL1Proxy.call(
            abi.encodeWithSelector(
                ISettlementL1.lockForOrder.selector,
                user, token, amount
            )
        );
        require(ok, "SettlementL2: cross-chain lock call failed");
        (success,) = abi.decode(ret, (bool, uint256));
        require(success, "SettlementL2: insufficient L1 balance to lock");

        // Update L1 cache after lock
        _refreshL1Cache(user, token);
    }

    /// @notice Refresh L1 cache for a user/token by reading SettlementL1.
    function _refreshL1Cache(address user, address token) internal {
        (bool ok, bytes memory ret) = settlementL1Proxy.call(
            abi.encodeWithSelector(
                ISettlementL1.getAvailableBalance.selector,
                user, token
            )
        );
        if (ok) {
            (uint256 free, uint256 locked) = abi.decode(ret, (uint256, uint256));
            margin.updateL1Cache(user, token, free, locked);
        }
    }

    function _recordTrade(
        address maker,
        address taker,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool crossChain
    ) internal returns (uint256 tradeId) {
        tradeId = nextTradeId++;
        uint256 price = quoteAmount * 1e18 / baseAmount;
        trades[tradeId] = TradeRecord({
            tradeId: tradeId,
            maker: maker,
            taker: taker,
            price: price,
            baseAmount: baseAmount,
            quoteAmount: quoteAmount,
            crossChain: crossChain,
            timestamp: block.timestamp
        });
        emit TradeSettled(tradeId, maker, taker, baseAmount, quoteAmount, crossChain);
    }

    event TradeSettled(
        uint256 indexed tradeId,
        address indexed maker,
        address indexed taker,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool crossChain
    );
}
