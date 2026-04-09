// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMarginL2} from "../interfaces/IMarginL2.sol";
import {ISettlementL1} from "../interfaces/ISettlementL1.sol";

contract MarginL2 is IMarginL2 {
    address public constant ETH = address(0);

    struct Balance {
        uint256 free;
        uint256 locked;
    }

    // token => user => Balance (L2-native)
    mapping(address => mapping(address => Balance)) internal _l2Balances;

    // Cached L1 Vault mirrors
    mapping(address => mapping(address => uint256)) public l1FreeCache;
    mapping(address => mapping(address => uint256)) public l1LockedCache;

    address public matchingEngine;
    address public settlement;
    address public settlementL1Proxy; // cross-chain proxy of SettlementL1
    address public owner;

    modifier onlyMatchingEngine() {
        require(msg.sender == matchingEngine, "MarginL2: not matching engine");
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == settlement, "MarginL2: not settlement");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == matchingEngine || msg.sender == settlement, "MarginL2: not authorized");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MarginL2: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setMatchingEngine(address _engine) external onlyOwner {
        matchingEngine = _engine;
    }

    function setSettlement(address _settlement) external onlyOwner {
        settlement = _settlement;
    }

    function setSettlementL1Proxy(address _proxy) external onlyOwner {
        settlementL1Proxy = _proxy;
    }

    function depositL2(address token, uint256 amount) external payable override {
        if (token == ETH) {
            require(msg.value == amount, "MarginL2: ETH mismatch");
        } else {
            require(msg.value == 0, "MarginL2: no ETH for token");
            (bool ok, bytes memory ret) = token.call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender, address(this), amount
                )
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "MarginL2: transfer failed");
        }
        _l2Balances[token][msg.sender].free += amount;
        emit L2Deposited(msg.sender, token, amount);
    }

    function withdrawL2(address token, uint256 amount) external override {
        Balance storage bal = _l2Balances[token][msg.sender];
        require(bal.free >= amount, "MarginL2: insufficient free balance");
        bal.free -= amount;

        if (token == ETH) {
            (bool ok,) = msg.sender.call{value: amount}("");
            require(ok, "MarginL2: ETH transfer failed");
        } else {
            (bool ok, bytes memory ret) = token.call(
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount)
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "MarginL2: transfer failed");
        }
        emit L2Withdrawn(msg.sender, token, amount);
    }

    function lockL2(address user, address token, uint256 amount) external override onlyAuthorized {
        Balance storage bal = _l2Balances[token][user];
        require(bal.free >= amount, "MarginL2: insufficient free to lock");
        bal.free -= amount;
        bal.locked += amount;
    }

    function unlockL2(address user, address token, uint256 amount) external override onlyAuthorized {
        Balance storage bal = _l2Balances[token][user];
        require(bal.locked >= amount, "MarginL2: insufficient locked");
        bal.locked -= amount;
        bal.free += amount;
    }

    function transferL2(
        address from,
        address to,
        address token,
        uint256 amount
    ) external override onlyAuthorized {
        Balance storage fromBal = _l2Balances[token][from];
        require(fromBal.free >= amount, "MarginL2: insufficient balance");
        fromBal.free -= amount;
        _l2Balances[token][to].free += amount;
    }

    function checkMargin(
        address user,
        address token,
        uint256 required,
        bool isL1Backed
    ) external view override returns (bool) {
        if (isL1Backed) {
            return l1FreeCache[token][user] >= required;
        }
        return _l2Balances[token][user].free >= required;
    }

    function freeBalanceL2(address user, address token) external view override returns (uint256) {
        return _l2Balances[token][user].free;
    }

    /// @notice Verify L1 balance via cross-chain call and update cache.
    function verifyAndUpdateL1Balance(
        address user,
        address token
    ) external returns (uint256 free, uint256 locked) {
        require(settlementL1Proxy != address(0), "MarginL2: L1 proxy not set");

        (bool ok, bytes memory ret) = settlementL1Proxy.call(
            abi.encodeWithSelector(
                ISettlementL1.getAvailableBalance.selector,
                user, token
            )
        );
        require(ok, "MarginL2: cross-chain balance check failed");
        (free, locked) = abi.decode(ret, (uint256, uint256));

        l1FreeCache[token][user] = free;
        l1LockedCache[token][user] = locked;
        emit L1CacheUpdated(user, token, free, locked);
    }

    function updateL1Cache(
        address user,
        address token,
        uint256 newFree,
        uint256 newLocked
    ) external override onlySettlement {
        l1FreeCache[token][user] = newFree;
        l1LockedCache[token][user] = newLocked;
        emit L1CacheUpdated(user, token, newFree, newLocked);
    }

    event L2Deposited(address indexed user, address indexed token, uint256 amount);
    event L2Withdrawn(address indexed user, address indexed token, uint256 amount);
    event L1CacheUpdated(address indexed user, address indexed token, uint256 free, uint256 locked);
}
