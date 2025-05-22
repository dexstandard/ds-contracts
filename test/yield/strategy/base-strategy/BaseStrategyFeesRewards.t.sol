// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {BaseStrategyHelper, VaultMultiStrategy} from "./BaseStrategyHelper.t.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";

contract BaseStrategyFeesRewardsTest is BaseStrategyHelper {
    VaultMultiStrategy private vault;
    MockStrategyV1 private strategy;

    uint256 private constant PLATFORM_FEE = 1e17; // 10 %
    uint256 private constant LOCK = 1 days;

    function setUp() external {
        setUpHelper();

        vault = _deployVault();
        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addrs = _getStrategyDeployAddresses(address(vault));
        strategy.initialize(rewards, addrs, STRATEGY_NAME, PLATFORM_FEE, LOCK);
    }

    /// balance below minAmounts ⇒ no fee taken
    function testChargeFeesBelowMinAmountNoTransfer() external {
        nativeToken.mint(address(strategy), 1 ether);

        vm.prank(strategyManager);
        strategy.setRewardMinAmount(address(nativeToken), 2 ether);

        strategy.chargeFeesCalled();

        uint256 managerBalBefore = nativeToken.balanceOf(strategyManager);

        vm.prank(strategyManager);
        strategy.harvest();

        assertEq(nativeToken.balanceOf(strategyManager), managerBalBefore, "unexpected fee transfer");
        assertTrue(!strategy.chargeFeesCalled(), "_chargeFees() should NOT be called");
    }

    function testAddRewardSuccess() external {
        address newReward = address(0x0123);
        vm.prank(strategyManager);
        strategy.addReward(newReward);

        assertEq(strategy.rewardsLength(), 3); // 2 default + 1
        // last element should be the one we just added
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("rewards(uint256)", 2));
        assertTrue(success);
        assertEq(abi.decode(data, (address)), newReward);
    }

    function testAddRewardRevertsForBaseOrNative() external {
        // baseToken
        vm.expectRevert(BaseStrategy.RewardIsBaseToken.selector);
        vm.prank(strategyManager);
        strategy.addReward(address(baseToken));

        // nativeToken
        vm.expectRevert(BaseStrategy.RewardIsNativeToken.selector);
        vm.prank(strategyManager);
        strategy.addReward(address(nativeToken));
    }

    function testAddRewardOnlyManager() external {
        address outsider = makeRandomUser();
        vm.expectRevert(BaseStrategy.NotStrategyManager.selector);
        vm.prank(outsider);
        strategy.addReward(address(0x0223));
    }

    function testRemoveReward() external {
        // starting array: [reward1, reward2]
        vm.prank(strategyManager);
        strategy.removeReward(0);

        assertEq(strategy.rewardsLength(), 1);
        // element 0 should now be the old element 1
        (, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("rewards(uint256)", 0));
        assertEq(abi.decode(data, (address)), reward2);
    }

    function testResetRewards() external {
        vm.prank(strategyManager);
        strategy.resetRewards();

        assertEq(strategy.rewardsLength(), 0);
    }

    function testSetRewardMinAmountOnlyManager() external {
        address user = makeRandomUser();
        vm.expectRevert(BaseStrategy.NotStrategyManager.selector);
        vm.prank(user);
        strategy.setRewardMinAmount(address(reward1), 123);

        vm.prank(strategyManager);
        strategy.setRewardMinAmount(address(reward1), 123);
        assertEq(strategy.minAmounts(address(reward1)), 123);
    }
}
