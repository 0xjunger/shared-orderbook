// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {
    function deposit(address token, uint256 amount) external payable;
    function withdraw(address token, uint256 amount) external;
    function lock(address user, address token, uint256 amount) external returns (bool);
    function unlock(address user, address token, uint256 amount) external returns (bool);
    function transfer(address from, address to, address token, uint256 amount) external returns (bool);
    function freeBalance(address user, address token) external view returns (uint256);
    function lockedBalance(address user, address token) external view returns (uint256);
}
