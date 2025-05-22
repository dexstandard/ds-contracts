// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {BaseStrategyHelper, VaultMultiStrategy} from "./BaseStrategyHelper.t.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";

contract BaseStrategyOwnershipTest is BaseStrategyHelper {
    VaultMultiStrategy public vault;
    MockStrategyV1 public strategy;

    address public newStrategyManager = address(0x123);

    function setUp() external {
        setUpHelper();

        vault = _deployVault();
        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addrs = _getStrategyDeployAddresses(address(vault));
        strategy.initialize(rewards, addrs, STRATEGY_NAME, 0, 1 days);
    }

    function testOnlyOwnerCanSetVault() public {
        address randomUser = makeRandomUser();
        vm.expectRevert(BaseStrategy.UnauthorizedOwner.selector);
        vm.prank(randomUser);
        strategy.setVault(newStrategyManager);
    }

    function testSetVaultUpdatesStateAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit BaseStrategy.SetVault(newStrategyManager);

        strategy.setVault(newStrategyManager);
        assertEq(strategy.vault(), newStrategyManager, "vault not updated");
    }

    function testOnlyOwnerCanSetSwapper() public {
        address randomUser = makeRandomUser();
        vm.expectRevert(BaseStrategy.UnauthorizedOwner.selector);
        vm.prank(randomUser);
        strategy.setSwapper(newStrategyManager);
    }

    function testSetSwapperUpdatesStateAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit BaseStrategy.SetSwapper(newStrategyManager);

        strategy.setSwapper(newStrategyManager);
        assertEq(strategy.swapper(), newStrategyManager, "swapper not updated");
    }

    function testOnlyOwnerCanChangeManager() public {
        address randomUser = makeRandomUser();
        vm.expectRevert(BaseStrategy.UnauthorizedOwner.selector);
        vm.prank(randomUser);
        strategy.setStrategyManager(newStrategyManager);
    }

    function testSetStrategyManagerUpdatesAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit BaseStrategy.SetStrategyManager(newStrategyManager);

        vm.prank(strategyManager);
        strategy.setStrategyManager(newStrategyManager);

        assertEq(strategy.strategyManager(), newStrategyManager, "manager not updated");
    }
}
