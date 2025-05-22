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

contract BaseStrategyHarvestTest is BaseStrategyHelper {
    address vault;
    MockStrategyV1 strategy;
    VaultMultiStrategy vaultContract;

    function setUp() external {
        setUpHelper();

        vaultContract = _deployVault();

        vault = address(vaultContract);
        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addresses = _getStrategyDeployAddresses(vault);

        strategy.initialize(rewards, addresses, STRATEGY_NAME, 0, 1 days);

        vaultContract.initialize(address(baseToken), address(strategy), strategyManager, "Test", "T");
    }

    function testHarvestOnlyStrategyManager() public {
        vm.prank(vault);
        vm.expectRevert(BaseStrategy.NotStrategyManager.selector);
        strategy.harvest();
    }

    function testHarvestRevertsWhenPaused() public {
        vm.prank(strategyManager);
        strategy.pause();

        vm.prank(strategyManager);
        vm.expectRevert(BaseStrategy.StrategyPaused.selector);
        strategy.harvest();

        vm.prank(strategyManager);
        strategy.unpause();
    }

    function testHarvestWithNativeExceedingMin() public {
        nativeToken.mint(address(strategy), 100 ether);

        vm.prank(strategyManager);
        strategy.setRewardMinAmount(address(nativeToken), 10 ether);

        vm.prank(strategyManager);
        strategy.harvest();

        assertTrue(strategy.chargeFeesCalled(), "Charge fees not triggered");
        assertTrue(strategy.swapNativeCalled(), "Swap native to base token not triggered");
    }

    function testLockLogic() public {
        baseToken.mint(address(strategy), 100 ether);
        vm.prank(vault);
        strategy.deposit();
        uint256 initialLocked = strategy.totalLocked(); //  100 ether
        uint256 lockDuration = strategy.lockDuration();
        vm.warp(block.timestamp + (lockDuration / 2));
        uint256 lockedNow = strategy.lockedProfit();
        assertApproxEqAbs(
            lockedNow, initialLocked / 2, 1e16, "Locked profit should be roughly half after half duration"
        );
    }
}
