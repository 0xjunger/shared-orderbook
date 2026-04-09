// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMarginL2 {
    function depositL2(address token, uint256 amount) external payable;
    function withdrawL2(address token, uint256 amount) external;
    function lockL2(address user, address token, uint256 amount) external;
    function unlockL2(address user, address token, uint256 amount) external;
    function transferL2(address from, address to, address token, uint256 amount) external;
    function checkMargin(address user, address token, uint256 required, bool isL1Backed) external view returns (bool);
    function freeBalanceL2(address user, address token) external view returns (uint256);
    function updateL1Cache(address user, address token, uint256 newFree, uint256 newLocked) external;
}
