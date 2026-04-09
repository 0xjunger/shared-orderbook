// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISettlementL1} from "../interfaces/ISettlementL1.sol";
import {IVault} from "../interfaces/IVault.sol";

contract SettlementL1 is ISettlementL1 {
    IVault public vault;
    address public owner;
    mapping(address => bool) public authorizedProxies;

    modifier onlyOwner() {
        require(msg.sender == owner, "SettlementL1: not owner");
        _;
    }

    modifier onlyAuthorizedProxy() {
        require(authorizedProxies[msg.sender], "SettlementL1: not authorized proxy");
        _;
    }

    constructor(address _vault) {
        vault = IVault(_vault);
        owner = msg.sender;
    }

    function setAuthorizedProxy(address proxy, bool status) external onlyOwner {
        authorizedProxies[proxy] = status;
    }

    /// @notice Settle a trade atomically on L1.
    /// Called via cross-chain proxy from SettlementL2.
    function settleTrade(
        address maker,
        address taker,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool makerIsBuy
    ) external override onlyAuthorizedProxy returns (bool) {
        if (makerIsBuy) {
            // Maker buys base (pays quote), taker sells base (receives quote)
            // Unlock maker's quote, transfer to taker
            require(vault.unlock(maker, quoteToken, quoteAmount), "SettlementL1: unlock maker quote failed");
            require(vault.transfer(maker, taker, quoteToken, quoteAmount), "SettlementL1: transfer quote failed");
            // Transfer taker's base to maker (taker must have free base in vault)
            require(vault.transfer(taker, maker, baseToken, baseAmount), "SettlementL1: transfer base failed");
        } else {
            // Maker sells base (receives quote), taker buys base (pays quote)
            // Unlock maker's base, transfer to taker
            require(vault.unlock(maker, baseToken, baseAmount), "SettlementL1: unlock maker base failed");
            require(vault.transfer(maker, taker, baseToken, baseAmount), "SettlementL1: transfer base failed");
            // Transfer taker's quote to maker
            require(vault.transfer(taker, maker, quoteToken, quoteAmount), "SettlementL1: transfer quote failed");
        }

        emit TradeSettled(maker, taker, baseToken, quoteToken, baseAmount, quoteAmount);
        return true;
    }

    /// @notice Lock collateral for a new order.
    function lockForOrder(
        address user,
        address token,
        uint256 amount
    ) external override onlyAuthorizedProxy returns (bool success, uint256 freeAfter) {
        success = vault.lock(user, token, amount);
        if (success) {
            freeAfter = vault.freeBalance(user, token);
        }
        emit CollateralLocked(user, token, amount);
    }

    /// @notice Release locked collateral on order cancellation.
    function releaseOnCancel(
        address user,
        address token,
        uint256 amount
    ) external override onlyAuthorizedProxy returns (bool) {
        require(vault.unlock(user, token, amount), "SettlementL1: unlock failed");
        emit CollateralReleased(user, token, amount);
        return true;
    }

    /// @notice Get a user's available balance in the vault.
    function getAvailableBalance(
        address user,
        address token
    ) external view override returns (uint256 free, uint256 locked) {
        free = vault.freeBalance(user, token);
        locked = vault.lockedBalance(user, token);
    }

    event TradeSettled(address indexed maker, address indexed taker, address baseToken, address quoteToken, uint256 baseAmount, uint256 quoteAmount);
    event CollateralLocked(address indexed user, address indexed token, uint256 amount);
    event CollateralReleased(address indexed user, address indexed token, uint256 amount);
}
