// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseVaultStrategyHelper} from "./BaseVaultStrategyHelper.t.sol";

contract VaultMultiStrategyUtilityTest is BaseVaultStrategyHelper {
    VaultMultiStrategy vault;
    MockERC20 baseToken;
    MockStrategyV1 strategy;

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategySwitched(address indexed oldStrategy, address indexed newStrategy);
    event StrategyManagerChanged(address indexed oldManager, address indexed newManager);

    function setUp() external {
        setUpHelper();

        baseToken = new MockERC20("WETH", "WETH");
        baseToken.mint(user1, 1000 ether);

        vault = _deployVault();

        strategy = _deployStrategy(address(vault), address(baseToken));

        vault.initialize(address(baseToken), address(strategy), strategyManager, NAME, SYMBOL);

        vm.startPrank(user1);
        baseToken.approve(address(vault), 500 ether);
        vault.deposit(500 ether);
        vm.stopPrank();
    }

    function testVaultBalanceCalculation() external {
        // user1 deposited 500 ethers and in all went to the strategy
        uint256 vaultBal = baseToken.balanceOf(address(vault));
        uint256 strategyBal = strategy.balanceOf();
        uint256 vaultComputed = vaultBal + strategyBal;

        uint256 vaultReported = vault.balance();
        assertEq(vaultReported, vaultComputed, "vault.balance() mismatch with vaultBal + strategyBal");
        assertEq(strategyBal, 500 ether, "strategyBal in not 500 ethers");
    }

    function testPricePerFullShareNoSupply() external {
        VaultMultiStrategy newVault = _deployVault();
        newVault.initialize(address(baseToken), address(strategy), strategyManager, NAME, SYMBOL);

        // newVault has totalSupply = 0 because no one deposited
        assertEq(newVault.totalSupply(), 0, "newVault has no deposits");

        uint256 pps = newVault.getPricePerFullShare();
        assertEq(pps, 1e18, "Price-per-share should be 1e18 if totalSupply=0");
    }

    function testGetPricePerFullShareAfterDeposit() external {
        // user1 has 500 shares, vault.totalSupply=500
        // vault total balance should also be ~500
        uint256 reportedPPS = vault.getPricePerFullShare();

        // ratio is 1:1 => pps = 1e18
        //     (balance() * 1e18) / totalSupply()
        uint256 vaultBal = vault.balance();
        uint256 ts = vault.totalSupply();
        uint256 expected = (vaultBal * 1e18) / ts;

        assertEq(reportedPPS, expected, "getPricePerFullShare mismatch");
        assertEq(reportedPPS, 1e18, "Should be 1e18 for no gains/losses");
    }

    function testEventStrategyAdded() external {
        MockStrategyV1 anotherStrat = _deployStrategy(address(vault), address(baseToken));

        vm.prank(strategyManager);

        vm.expectEmit(true, true, false, true);
        emit StrategyAdded(address(anotherStrat));

        vault.addStrategy(address(anotherStrat));
    }

    function testEventStrategyRemoved() external {
        MockStrategyV1 anotherStrat = _deployStrategy(address(vault), address(baseToken));

        vm.prank(strategyManager);
        vault.addStrategy(address(anotherStrat));

        vm.prank(strategyManager);
        vm.expectEmit(true, true, false, true);
        emit StrategyRemoved(address(anotherStrat));

        vault.removeStrategy(address(anotherStrat));
    }

    function testEventStrategySwitched() external {
        MockStrategyV1 anotherStrat = _deployStrategy(address(vault), address(baseToken));

        vm.prank(strategyManager);
        vault.addStrategy(address(anotherStrat));

        vm.expectEmit(true, true, false, true);
        emit StrategySwitched(address(strategy), address(anotherStrat));

        vm.prank(strategyManager);
        vault.switchStrategy(address(anotherStrat));
    }

    function testEventStrategyManagerChanged() external {
        address oldMgr = vault.strategyManager();
        address newMgr = address(101);

        vm.expectEmit(true, true, false, true);
        emit StrategyManagerChanged(oldMgr, newMgr);

        vault.setStrategyManager(newMgr);
        assertEq(vault.strategyManager(), newMgr, "manager not updated");
    }
}
