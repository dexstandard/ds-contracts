// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseStrategyHelper, VaultMultiStrategy} from "./BaseStrategyHelper.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";

contract BaseStrategyDepositTest is BaseStrategyHelper {
    address vault;
    MockStrategyV1 strategy;

    function setUp() external {
        setUpHelper();

        vault = address(_deployVault());

        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);

        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);
    }

    function testDepositNoBalanceDoesNothing() external {
        uint256 balBefore = strategy.balanceOf();

        vm.recordLogs();
        strategy.deposit();

        // The strategy balance should remain the same.
        uint256 balAfter = strategy.balanceOf();
        assertEq(balAfter, balBefore, "Balance shouldn't change if no base tokens on hand");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No events should be emitted if no deposit happened");
    }

    function testDepositWhenPausedReverts() external {
        vm.prank(strategyManager);
        strategy.pause();

        // deposit should revert with StrategyPaused
        vm.expectRevert(BaseStrategy.StrategyPaused.selector);
        strategy.deposit();
    }

    function testDepositWithPositiveBalance() external {
        baseToken.mint(address(strategy), 500 ether);

        // strategy has 500 tokens
        assertEq(baseToken.balanceOf(address(strategy)), 500 ether, "Strategy should have 500 base tokens on-hand");

        uint256 balBefore = strategy.balanceOf();
        assertEq(balBefore, 500 ether, "Initial strategy balanceOf mismatch");

        vm.recordLogs();

        strategy.deposit();

        // strategy.balanceOf() should now be 500
        uint256 balAfter = strategy.balanceOf();
        assertEq(balAfter, 500 ether, "Did not deposit the on-hand base tokens into _balanceInStrategy");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // The deposit logic should have emitted 1 event: Deposit(uint256 tvl)
        assertEq(logs.length, 1, "Should have emitted exactly 1 event (Deposit)");

        Vm.Log memory logEntry = logs[0];
        bytes32 depositSig = keccak256("Deposit(uint256)");
        require(logEntry.topics[0] == depositSig, "Not a Deposit event signature");

        (uint256 tvlEmitted) = abi.decode(logEntry.data, (uint256));
        assertEq(tvlEmitted, balAfter, "Deposit event mismatch on tvl");
    }
}
