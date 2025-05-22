// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {BaseStrategyHelper, VaultMultiStrategy} from "./BaseStrategyHelper.t.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";

contract BaseStrategyPauseEmergencyTest is BaseStrategyHelper {
    VaultMultiStrategy private vault;
    MockStrategyV1 private strategy;

    uint256 private constant PLATFORM_FEE = 0;
    uint256 private constant LOCK = 1 days;

    function setUp() external {
        setUpHelper();

        vault = _deployVault();
        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addrs = _getStrategyDeployAddresses(address(vault));
        strategy.initialize(rewards, addrs, STRATEGY_NAME, PLATFORM_FEE, LOCK);
    }

    function testPauseOnlyManager() external {
        address randomUser = makeRandomUser();
        vm.expectRevert(BaseStrategy.NotStrategyManager.selector);
        vm.prank(randomUser);
        strategy.pause();

        vm.prank(strategyManager);
        strategy.pause();
        assertTrue(strategy.paused());
    }

    function testDepositAndHarvestRevertWhenPaused() external {
        vm.prank(strategyManager);
        strategy.pause();

        vm.expectRevert(BaseStrategy.StrategyPaused.selector);
        strategy.deposit();

        vm.expectRevert(BaseStrategy.StrategyPaused.selector);
        vm.prank(strategyManager);
        strategy.harvest();
    }

    function testPanicWithdrawsAndPauses() external {
        baseToken.mint(address(strategy), 20 ether);
        strategy.deposit();

        assertEq(strategy.balanceOf(), 20 ether, "precondition");

        vm.prank(strategyManager);
        strategy.panic();

        assertTrue(strategy.paused());

        assertEq(strategy.balanceOfPool(), 0, "pool should be 0 after panic");
        assertEq(strategy.balanceOfBaseToken(), 20 ether, "strategy balance should be 20 after panic");
    }

    function testRetireStrategyOnlyVault() external {
        address outsider = makeRandomUser();
        vm.expectRevert(BaseStrategy.NotVault.selector);
        vm.prank(outsider);
        strategy.retireStrategy();
    }

    function testRetireStrategyTransfersIdleBase() external {
        baseToken.mint(address(strategy), 30 ether);
        strategy.deposit();

        baseToken.mint(address(strategy), 5 ether);

        uint256 vaultBalBefore = baseToken.balanceOf(address(vault));

        vm.prank(address(vault));
        strategy.retireStrategy();

        assertEq(strategy.balanceOfPool(), 0);

        assertEq(baseToken.balanceOf(address(vault)) - vaultBalBefore, 35 ether);
        assertEq(baseToken.balanceOf(address(strategy)), 0);
    }
}
