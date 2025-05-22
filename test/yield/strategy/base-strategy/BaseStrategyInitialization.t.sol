// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseStrategyHelper, VaultMultiStrategy} from "./BaseStrategyHelper.t.sol";

contract BaseStrategyInitializationTest is BaseStrategyHelper {
    address vault;

    function setUp() external {
        setUpHelper();
    }

    function testInitializeHappyPath() external {
        vault = address(_deployVault());

        MockStrategyV1 strategy = _deployStrategy();

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);

        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);

        VaultMultiStrategy(vault).initialize(address(baseToken), address(strategy), strategyManager, NAME, SYMBOL);

        assertEq(strategy.baseToken(), address(baseToken), "baseToken mismatch");
        assertEq(strategy.nativeToken(), address(nativeToken), "nativeToken mismatch");
        assertEq(strategy.vault(), vault, "vault mismatch");
        assertEq(strategy.swapper(), swapper, "swapper mismatch");
        assertEq(strategy.strategyManager(), strategyManager, "manager mismatch");
        assertEq(strategy.lockDuration(), 1 days, "lockDuration mismatch");
        bool isHarvestOnDeposit = strategy.harvestOnDeposit();
        assertFalse(isHarvestOnDeposit, "harvestOnDeposit should default false");

        assertEq(strategy.rewards(0), reward1, "reward1 mismatch");
        assertEq(strategy.rewards(1), reward2, "reward2 mismatch");

        assertEq(strategy.strategyName(), STRATEGY_NAME, "Name mismatch");
    }

    function testInitializeZeroVaultReverts() external {
        MockStrategyV1 strategy = _deployStrategy();
        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(address(0));

        vm.expectRevert(bytes("Invalid vault"));
        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);
    }

    function testInitializeRewardIsBaseTokenReverts() external {
        vault = address(_deployVault());

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);
        MockStrategyV1 strategy = _deployStrategy();
        vm.expectRevert(BaseStrategy.RewardIsBaseToken.selector);

        address[] memory rewards = new address[](1);
        rewards[0] = address(baseToken);

        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);
    }

    function testInitializeRewardIsNativeTokenReverts() external {
        vault = address(_deployVault());

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);
        MockStrategyV1 strategy = _deployStrategy();
        vm.expectRevert(BaseStrategy.RewardIsNativeToken.selector);

        address[] memory rewards = new address[](1);
        rewards[0] = address(nativeToken);

        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);
    }

    function testSetHarvestOnDeposit() external {
        vault = address(_deployVault());

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);
        MockStrategyV1 strategy = _deployStrategy();
        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);

        // Initially, lockDuration=1 days, harvestOnDeposit=false
        assertEq(strategy.lockDuration(), 1 days, "initial lockDuration mismatch");
        bool onDeposit = strategy.harvestOnDeposit();
        assertFalse(onDeposit, "Should be false initially");

        vm.prank(strategyManager);
        strategy.setHarvestOnDeposit(true);

        assertEq(strategy.lockDuration(), 0, "Should have lockDuration=0 after harvestOnDeposit= true");
        assertTrue(strategy.harvestOnDeposit(), "harvestOnDeposit not set to true");
    }
}
