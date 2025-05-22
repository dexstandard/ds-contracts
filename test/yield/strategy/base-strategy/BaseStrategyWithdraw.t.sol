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

contract BaseStrategyWithdrawTest is BaseStrategyHelper {
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

    function testWithdrawRevertsWhenNotCalledByVault() public {
        baseToken.mint(address(strategy), 100 ether);

        vm.prank(address(0x1234));
        vm.expectRevert(BaseStrategy.NotVault.selector);
        strategy.withdraw(50 ether);
    }

    function testWithdrawWithSufficientCurrentBalance() public {
        baseToken.mint(address(strategy), 200 ether);
        uint256 currentBalance = strategy.balanceOfBaseToken();
        assertEq(currentBalance, 200 ether, "balance should be 200 ether");

        vm.prank(vault);
        strategy.withdraw(150 ether);

        uint256 remainingBalance = strategy.balanceOfBaseToken();
        assertEq(remainingBalance, 50 ether, "Remaining balance should be 50 ether");
    }

    function testWithdrawPartialTriggeringInternalWithdraw() public {
        baseToken.mint(address(strategy), 50 ether);
        vm.prank(vault);
        strategy.withdraw(100 ether);

        uint256 remaining = strategy.balanceOfBaseToken();
        assertEq(remaining, 0, "balance should be 0 after withdrawal");

        uint256 vaultBalance = vaultContract.balance();

        assertEq(vaultBalance, 50 ether, "Total vault balance should be 50 ether after withdrawal");
    }

    function testWithdrawEmitsEvent() public {
        baseToken.mint(address(strategy), 120 ether);

        vm.prank(vault);
        vm.recordLogs();
        strategy.withdraw(60 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSig = keccak256("Withdraw(uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == expectedSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Withdraw event was not emitted");
    }
}
