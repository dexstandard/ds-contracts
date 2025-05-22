// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseVaultStrategyHelper} from "./BaseVaultStrategyHelper.t.sol"; // The helper with _deployVault() etc.

contract VaultMultiStrategyWithdrawTest is BaseVaultStrategyHelper {
    VaultMultiStrategy vault;
    MockERC20 baseToken;
    MockStrategyV1 strategy;

    function setUp() external {
        setUpHelper();

        baseToken = new MockERC20("WETH", "WETH");
        baseToken.mint(user1, 1_000 ether);
        baseToken.mint(user2, 500 ether);

        vault = _deployVault();

        strategy = _deployStrategy(address(vault), address(baseToken));

        vault.initialize(address(baseToken), address(strategy), strategyManager, NAME, SYMBOL);

        // We do an initial deposit from user1 so there's some balance in the vault/strategy
        vm.startPrank(user1);
        baseToken.approve(address(vault), 300 ether);
        vault.deposit(300 ether); // user1 deposits 300 => user1 gets 300 shares
        vm.stopPrank();
    }

    function testWithdrawZeroSharesReverts() external {
        // user1 tries to withdraw zero
        vm.prank(user1);
        vm.expectRevert(bytes("Cannot withdraw zero shares"));
        vault.withdraw(0);
    }

    function testWithdrawPartial() external {
        // user1 currently has 300 shares from the setUp deposit
        // We'll withdraw 100 shares
        uint256 sharesToWithdraw = 100 ether;

        // Check user1's starting baseToken balance
        uint256 userBalBefore = baseToken.balanceOf(user1);

        // user1 calls withdraw(100)
        vm.prank(user1);
        vault.withdraw(sharesToWithdraw);

        // Check user1's share balance decreased
        uint256 userSharesAfter = vault.balanceOf(user1);
        assertEq(userSharesAfter, 200 ether, "user1 should have 200 shares left");

        // The user's baseToken balance should have increased by 100 * pricePerShare
        // Because pricePerShare is 1:1 right now (no yield, no second deposit),
        // user1 should get exactly 100 baseToken back.
        uint256 userBalAfter = baseToken.balanceOf(user1);
        assertEq(userBalAfter - userBalBefore, 100 ether, "user1 baseToken increase mismatch");

        // The vault's totalSupply is now 200
        assertEq(vault.totalSupply(), 200 ether, "vault totalSupply mismatch after partial withdraw");

        // The vault's balance() is 200
        assertEq(vault.balance(), 200 ether, "vault balance mismatch after partial withdraw");
    }

    function testWithdrawRequiresStrategyPull() external {
        uint256 vaultBalBefore = baseToken.balanceOf(address(vault));
        uint256 stratBalBefore = strategy.balanceOf();

        // earn() was called in the deposit flow => vaultBalBefore === 0
        assertEq(vaultBalBefore, 0 ether, "Vault should not have free amounts");

        uint256 userBalBefore = baseToken.balanceOf(user1);

        vm.prank(user1);
        vault.withdraw(300 ether);

        uint256 userBalAfter = baseToken.balanceOf(user1);
        uint256 gained = userBalAfter - userBalBefore;
        assertEq(gained, 300 ether, "user1 didn't get 300 tokens back");

        assertEq(vault.balanceOf(user1), 0, "user1 shares should be 0");

        assertEq(vault.totalSupply(), 0, "vault totalSupply mismatch after full withdraw");

        // check that vault pull from the strategy
        uint256 stratBalAfter = strategy.balanceOf();
        uint256 stratLost = stratBalBefore - stratBalAfter;
        assertGt(stratLost, 300, "Strategy balance didn't decrease at all");
    }

    function testWithdrawAllMatchesManualWithdraw() external {
        uint256 userBalBefore = baseToken.balanceOf(user1);
        vm.startPrank(user1);
        vault.withdrawAll();
        vm.stopPrank();

        uint256 userBalAfterAll = baseToken.balanceOf(user1);
        uint256 gainedAll = userBalAfterAll - userBalBefore;

        // user1 has 0 shares
        assertEq(vault.balanceOf(user1), 0, "user1 shares not zero after withdrawAll");
        assertEq(gainedAll, 300 ether, "user didn't receive 300 ethers");

        vm.startPrank(user1);
        baseToken.approve(address(vault), 300 ether);
        vault.deposit(300 ether);

        uint256 userBalBefore2 = baseToken.balanceOf(user1);

        uint256 userShares = vault.balanceOf(user1);
        vault.withdraw(userShares);
        vm.stopPrank();

        uint256 userBalAfter2 = baseToken.balanceOf(user1);
        uint256 gainedManual = userBalAfter2 - userBalBefore2;

        assertEq(gainedManual, 300 ether, "Manual withdraw gained mismatch");
    }
}
