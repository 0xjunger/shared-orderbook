// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVault} from "../interfaces/IVault.sol";

contract Vault is IVault {
    address public constant ETH = address(0);

    struct Balance {
        uint256 free;
        uint256 locked;
    }

    // token => user => Balance
    mapping(address => mapping(address => Balance)) internal _balances;
    mapping(address => bool) public authorized;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Vault: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Vault: not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setAuthorized(address addr, bool status) external onlyOwner {
        authorized[addr] = status;
    }

    function deposit(address token, uint256 amount) external payable override {
        if (token == ETH) {
            require(msg.value == amount, "Vault: ETH mismatch");
            _balances[ETH][msg.sender].free += amount;
        } else {
            require(msg.value == 0, "Vault: no ETH for token deposit");
            (bool ok, bytes memory ret) = token.call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender, address(this), amount
                )
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "Vault: transfer failed");
            _balances[token][msg.sender].free += amount;
        }
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external override {
        Balance storage bal = _balances[token][msg.sender];
        require(bal.free >= amount, "Vault: insufficient free balance");
        bal.free -= amount;

        if (token == ETH) {
            (bool ok,) = msg.sender.call{value: amount}("");
            require(ok, "Vault: ETH transfer failed");
        } else {
            (bool ok, bytes memory ret) = token.call(
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount)
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "Vault: transfer failed");
        }
        emit Withdrawn(msg.sender, token, amount);
    }

    function lock(address user, address token, uint256 amount) external override onlyAuthorized returns (bool) {
        Balance storage bal = _balances[token][user];
        if (bal.free < amount) return false;
        bal.free -= amount;
        bal.locked += amount;
        emit Locked(user, token, amount);
        return true;
    }

    function unlock(address user, address token, uint256 amount) external override onlyAuthorized returns (bool) {
        Balance storage bal = _balances[token][user];
        if (bal.locked < amount) return false;
        bal.locked -= amount;
        bal.free += amount;
        emit Unlocked(user, token, amount);
        return true;
    }

    function transfer(
        address from,
        address to,
        address token,
        uint256 amount
    ) external override onlyAuthorized returns (bool) {
        Balance storage fromBal = _balances[token][from];
        if (fromBal.free < amount) return false;
        fromBal.free -= amount;
        _balances[token][to].free += amount;
        emit Transferred(from, to, token, amount);
        return true;
    }

    function freeBalance(address user, address token) external view override returns (uint256) {
        return _balances[token][user].free;
    }

    function lockedBalance(address user, address token) external view override returns (uint256) {
        return _balances[token][user].locked;
    }

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event Locked(address indexed user, address indexed token, uint256 amount);
    event Unlocked(address indexed user, address indexed token, uint256 amount);
    event Transferred(address indexed from, address indexed to, address indexed token, uint256 amount);
}
