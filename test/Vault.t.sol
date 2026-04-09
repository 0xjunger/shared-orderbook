// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Vault} from "../src/l1/Vault.sol";

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract VaultTest is Test {
    Vault vault;
    MockERC20 token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address authorized = makeAddr("authorized");

    function setUp() public {
        vault = new Vault();
        token = new MockERC20();
        vault.setAuthorized(authorized, true);
    }

    // --- Deposit ---

    function test_depositETH() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 5 ether}(address(0), 5 ether);
        assertEq(vault.freeBalance(alice, address(0)), 5 ether);
    }

    function test_depositToken() public {
        token.mint(alice, 1000e18);
        vm.startPrank(alice);
        token.approve(address(vault), 500e18);
        vault.deposit(address(token), 500e18);
        vm.stopPrank();
        assertEq(vault.freeBalance(alice, address(token)), 500e18);
    }

    function test_depositETH_revert_mismatch() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert("Vault: ETH mismatch");
        vault.deposit{value: 3 ether}(address(0), 5 ether);
    }

    // --- Withdraw ---

    function test_withdrawETH() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 5 ether}(address(0), 5 ether);

        vm.prank(alice);
        vault.withdraw(address(0), 3 ether);
        assertEq(vault.freeBalance(alice, address(0)), 2 ether);
        assertEq(alice.balance, 8 ether);
    }

    function test_withdraw_revert_insufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.deposit{value: 1 ether}(address(0), 1 ether);

        vm.prank(alice);
        vm.expectRevert("Vault: insufficient free balance");
        vault.withdraw(address(0), 2 ether);
    }

    // --- Lock / Unlock ---

    function test_lock_unlock() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(address(0), 10 ether);

        vm.prank(authorized);
        bool ok = vault.lock(alice, address(0), 4 ether);
        assertTrue(ok);
        assertEq(vault.freeBalance(alice, address(0)), 6 ether);
        assertEq(vault.lockedBalance(alice, address(0)), 4 ether);

        vm.prank(authorized);
        ok = vault.unlock(alice, address(0), 2 ether);
        assertTrue(ok);
        assertEq(vault.freeBalance(alice, address(0)), 8 ether);
        assertEq(vault.lockedBalance(alice, address(0)), 2 ether);
    }

    function test_lock_insufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.deposit{value: 1 ether}(address(0), 1 ether);

        vm.prank(authorized);
        bool ok = vault.lock(alice, address(0), 2 ether);
        assertFalse(ok);
    }

    function test_lock_revert_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert("Vault: not authorized");
        vault.lock(alice, address(0), 1 ether);
    }

    // --- Transfer ---

    function test_transfer() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(address(0), 10 ether);

        vm.prank(authorized);
        bool ok = vault.transfer(alice, bob, address(0), 3 ether);
        assertTrue(ok);
        assertEq(vault.freeBalance(alice, address(0)), 7 ether);
        assertEq(vault.freeBalance(bob, address(0)), 3 ether);
    }

    function test_transfer_insufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.deposit{value: 1 ether}(address(0), 1 ether);

        vm.prank(authorized);
        bool ok = vault.transfer(alice, bob, address(0), 5 ether);
        assertFalse(ok);
    }

    // --- Cannot withdraw locked ---

    function test_cannot_withdraw_locked() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(address(0), 10 ether);

        vm.prank(authorized);
        vault.lock(alice, address(0), 8 ether);

        vm.prank(alice);
        vm.expectRevert("Vault: insufficient free balance");
        vault.withdraw(address(0), 5 ether);

        // Can withdraw free portion
        vm.prank(alice);
        vault.withdraw(address(0), 2 ether);
        assertEq(vault.freeBalance(alice, address(0)), 0);
    }
}
