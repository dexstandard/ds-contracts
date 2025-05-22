// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {IStrategyV1} from "../../../src/yield/interfaces/strategy/IStrategyV1.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseStrategy} from "../../../src/yield/strategies/BaseStrategy.sol";
import {BaseVaultStrategyHelper} from "./BaseVaultStrategyHelper.t.sol";

contract VaultMultiStrategyDepositTest is BaseVaultStrategyHelper {
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

        assertEq(vault.baseToken(), address(baseToken), "baseToken mismatch");
        assertEq(vault.activeStrategy(), address(strategy), "activeStrategy mismatch");
        assertEq(vault.strategyManager(), strategyManager, "strategyManager mismatch");
    }

    function testDepositZeroReverts() external {
        vm.prank(user1);
        vm.expectRevert(bytes("Cannot deposit zero"));
        vault.deposit(0);
    }

    function testFirstDeposit() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vault.deposit(amount);
        vm.stopPrank();

        // Because totalSupply was zero, user1 gets `amount` shares minted
        assertEq(vault.balanceOf(user1), amount, "User1 shares mismatch");
        assertEq(vault.totalSupply(), amount, "Vault totalSupply mismatch");

        // The vault's total balance should now be 100
        assertEq(vault.balance(), amount, "Vault total balance mismatch");

        // The mock strategy should hold the deposit in `_balance`
        uint256 stratBal = strategy.balanceOf();
        assertEq(stratBal, amount, "Strategy balance mismatch");
    }

    function testSecondDeposit() external {
        // user1 deposits 100 tokens
        vm.startPrank(user1);
        baseToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vm.stopPrank();

        // user1 should have 100 shares
        assertEq(vault.balanceOf(user1), 100 ether);

        // The vault total supply is 100
        assertEq(vault.totalSupply(), 100 ether);

        // user2 now deposits 50 tokens
        vm.startPrank(user2);
        baseToken.approve(address(vault), 50 ether);
        vault.deposit(50 ether);
        vm.stopPrank();

        // The current pool balance before user2 deposit was 100
        // The share ratio is totalSupply/poolBalance = 100/100 = 1
        // So user2 should get 50 shares for 50 tokens
        assertEq(vault.balanceOf(user2), 50 ether, "User2 shares mismatch");

        // Vault total supply is now 150
        assertEq(vault.totalSupply(), 150 ether, "Vault totalSupply mismatch after 2 deposits");

        // The combined vault balance is 150
        assertEq(vault.balance(), 150 ether, "Vault total balance mismatch");

        // The strategy's final recorded balanceOf() should be 150
        assertEq(strategy.balanceOf(), 150 ether, "Strategy final balance mismatch");
    }

    function testMultipleDepositsBySameUser() external {
        // user2 first deposit of 200
        vm.startPrank(user2);
        baseToken.approve(address(vault), 500 ether);
        vault.deposit(200 ether);

        // totalSupply = 200, user2 has 200 shares
        assertEq(vault.totalSupply(), 200 ether);
        assertEq(vault.balanceOf(user2), 200 ether);

        // deposit again 100
        vault.deposit(100 ether);
        vm.stopPrank();

        // Before the second deposit, pool was 200, totalSupply was 200 => ratio is 1:1
        // So depositing 100 means user2 gets 100 shares
        // user2 total shares: 300
        // vault totalSupply: 300
        assertEq(vault.balanceOf(user2), 300 ether, "User2 final shares mismatch");
        assertEq(vault.totalSupply(), 300 ether, "Vault totalSupply mismatch");

        // The final vault balance and strategy balance should be 300
        assertEq(vault.balance(), 300 ether, "Vault final balance mismatch");
        assertEq(strategy.balanceOf(), 300 ether, "Strategy final balance mismatch");
    }

    function testFuzzDeposit() external {
        uint256 depositAmount = 1e30;

        address user = address(0x123);

        baseToken.mint(user, depositAmount);

        vm.startPrank(user);
        baseToken.approve(address(vault), depositAmount);

        vault.deposit(depositAmount);

        assertEq(vault.balanceOf(user), depositAmount);

        vm.stopPrank();
    }

    function testFuzzDepositWithdrawCycle(uint96 amt1, uint96 amt2) external {
        address randomUser = makeRandomUser();

        uint256 deposit1 = bound(uint256(amt1), 1, 1e24);
        uint256 deposit2 = bound(uint256(amt2), 1, 1e24);

        baseToken.mint(randomUser, deposit1 + deposit2);

        vm.startPrank(randomUser);
        baseToken.approve(address(vault), deposit1 + deposit2);
        vault.deposit(deposit1);

        uint256 userShares1 = vault.balanceOf(randomUser);
        if (userShares1 > 0) {
            uint256 halfShares = userShares1 / 2;
            if (halfShares == 0) {
                vm.stopPrank();
                return;
            }
            vault.withdraw(halfShares);
        }

        vault.deposit(deposit2);
        vm.stopPrank();

        uint256 totalBalance = vault.balance();
        uint256 totalSupply = vault.totalSupply();
        uint256 computedPPS = totalSupply == 0 ? 1e18 : (totalBalance * 1e18) / totalSupply;

        uint256 reportedPPS = vault.getPricePerFullShare();

        assertEq(reportedPPS, computedPPS, "Price per share does not match computed value");
    }

    function testDepositExceedsUserBalanceReverts() external {
        vm.startPrank(user1);

        // user1 has 1000, but tries depositing 2000
        baseToken.approve(address(vault), 2_000 ether);

        vm.expectRevert();
        vault.deposit(2_000 ether);

        vm.stopPrank();
    }

    function testDepositInsufficientAllowanceReverts() external {
        vm.startPrank(user1);

        // user1 does NOT call approve or approves less than deposit
        baseToken.approve(address(vault), 50 ether);

        // Attempting to deposit 100
        vm.expectRevert();
        vault.deposit(100 ether);

        vm.stopPrank();
    }

    function testDepositWhileStrategyPausedReverts() external {
        // Pause the strategy
        vm.prank(strategyManager);
        strategy.pause();

        // user1 tries to deposit
        vm.startPrank(user1);
        baseToken.approve(address(vault), 100 ether);

        vm.expectRevert();
        vault.deposit(100 ether);

        vm.stopPrank();
    }

    function testEarnTransfersTokens() external {
        baseToken.mint(address(vault), 100 ether);

        uint256 vaultBalBefore = baseToken.balanceOf(address(vault));
        assertEq(vaultBalBefore, 100 ether, "Vault should have 100 extra tokens");

        vm.prank(user1);
        vault.earn();

        uint256 vaultBalAfter = baseToken.balanceOf(address(vault));
        assertEq(vaultBalAfter, 0, "Vault should have zero tokens after earn()");

        uint256 stratBal = strategy.balanceOf();
        assertEq(stratBal, 100 ether, "Strategy should have received the extra tokens");
    }

    function testEarnDoesNothingIfNoTokens() external {
        uint256 vaultBalBefore = baseToken.balanceOf(address(vault));
        assertEq(vaultBalBefore, 0, "Vault should have zero tokens initially");

        uint256 stratBalBefore = strategy.balanceOf();

        vm.prank(user1);
        vault.earn();

        uint256 vaultBalAfter = baseToken.balanceOf(address(vault));
        assertEq(vaultBalAfter, 0, "Vault should still have zero tokens");

        uint256 stratBalAfter = strategy.balanceOf();
        assertEq(stratBalAfter, stratBalBefore, "Strategy balance should remain unchanged");
    }
}
