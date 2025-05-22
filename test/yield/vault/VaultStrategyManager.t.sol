// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseVaultStrategyHelper} from "./BaseVaultStrategyHelper.t.sol"; // Deploys the vault, strategy, etc.

error OwnableUnauthorizedAccount(address account);

event StrategySwitched(address indexed oldStrategy, address indexed newStrategy);

event StrategyManagerChanged(address indexed oldManager, address indexed newManager);

contract VaultMultiStrategyManagerTest is BaseVaultStrategyHelper {
    VaultMultiStrategy vault;
    MockERC20 baseToken;
    MockStrategyV1 strategyA;
    MockStrategyV1 strategyB;

    function setUp() external {
        setUpHelper();

        baseToken = new MockERC20("WETH", "WETH");

        vault = _deployVault();

        strategyA = _deployStrategy(address(vault), address(baseToken));

        vault.initialize(address(baseToken), address(strategyA), strategyManager, NAME, SYMBOL);

        baseToken.mint(user1, 1000 ether);
        vm.startPrank(user1);
        baseToken.approve(address(vault), 500 ether);
        vault.deposit(500 ether);
        vm.stopPrank();

        strategyB = _deployStrategy(address(vault), address(baseToken));
    }

    function testAddStrategyNonManagerReverts() external {
        vm.prank(user1); // not the strategyManager
        vm.expectRevert(VaultMultiStrategy.NotStrategyManager.selector);
        vault.addStrategy(address(strategyB));
    }

    function testRemoveStrategyNonManagerReverts() external {
        vm.prank(user1);
        vm.expectRevert(VaultMultiStrategy.NotStrategyManager.selector);
        vault.removeStrategy(address(strategyA));
    }

    function testSwitchStrategyNonManagerReverts() external {
        vm.prank(user1);
        vm.expectRevert(VaultMultiStrategy.NotStrategyManager.selector);
        vault.switchStrategy(address(strategyB));
    }

    /// Add a valid strategy
    function testAddStrategySuccess() external {
        vm.prank(strategyManager);
        vault.addStrategy(address(strategyB));

        address[] memory strats = getStrategies(address(vault));
        assertEq(strats.length, 2, "should have 2 strategies");
        assertEq(strats[0], address(strategyA));
        assertEq(strats[1], address(strategyB));
    }

    function testAddStrategyBaseTokenMismatchReverts() external {
        MockERC20 differentToken = new MockERC20("DAI", "DAI");
        MockStrategyV1 mismatchStrategy = _deployStrategy(address(vault), address(differentToken));

        vm.prank(strategyManager);
        vm.expectRevert(bytes("Strategy base token mismatch"));
        vault.addStrategy(address(mismatchStrategy));
    }

    function testRemoveActiveStrategyReverts() external {
        vm.prank(strategyManager);
        vm.expectRevert(bytes("Cannot remove active strategy"));
        vault.removeStrategy(address(strategyA));
    }

    function testRemoveStrategySuccess() external {
        vm.prank(strategyManager);
        vault.addStrategy(address(strategyB));

        vm.prank(strategyManager);
        vault.removeStrategy(address(strategyB));

        address[] memory strats = getStrategies(address(vault));
        assertEq(strats.length, 1, "should have 1 strategy");
        assertEq(strats[0], address(strategyA));
    }

    function testSwitchStrategyNotFoundReverts() external {
        vm.prank(strategyManager);
        vm.expectRevert(bytes("Strategy not added to vault"));
        vault.switchStrategy(address(strategyB));
    }

    function testSwitchStrategySameAsActiveReverts() external {
        vm.prank(strategyManager);
        vm.expectRevert(bytes("Already the active strategy"));
        vault.switchStrategy(address(strategyA));
    }

    /// Switch from strategyA to strategyB
    /// - check old strategy is fully withdrawn
    /// - check new strategy is deposited
    /// - verify event
    function testSwitchStrategySuccess() external {
        vm.prank(strategyManager);
        vault.addStrategy(address(strategyB));

        uint256 oldStratBalBefore = strategyA.balanceOf();
        assertEq(oldStratBalBefore, 500 ether, "Mismatched balance");

        // 3) manager calls switchStrategy
        vm.expectEmit(true, true, false, true);
        emit StrategySwitched(address(strategyA), address(strategyB));

        vm.prank(strategyManager);
        vault.switchStrategy(address(strategyB));

        // after switching, confirm old strategy is 0
        uint256 oldStratBalAfter = strategyA.balanceOf();
        assertEq(oldStratBalAfter, 0, "old strategy did not withdraw everything");

        // new strategy is the active one
        assertEq(vault.activeStrategy(), address(strategyB), "strategyB not set as active strategy");

        // vault funds are now in strategyB
        uint256 newStratBal = strategyB.balanceOf();
        assertEq(newStratBal, oldStratBalBefore, "New strategy does not have the old strategy's funds");
    }

    function testSetStrategyManagerNonOwnerReverts() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));
        vault.setStrategyManager(user1);
    }

    function testSetStrategyManagerZeroReverts() external {
        vm.expectRevert(bytes("Invalid manager address"));
        vault.setStrategyManager(address(0));
    }

    function testSetStrategyManagerSuccess() external {
        vm.expectEmit(true, true, false, true);
        emit StrategyManagerChanged(strategyManager, user1);

        vault.setStrategyManager(user1);
        assertEq(vault.strategyManager(), user1, "Strategy manager not updated");
    }

    function testRescueStuckTokenSuccess() external {
        MockERC20 otherToken = new MockERC20("Other", "OTH");
        otherToken.mint(address(vault), 1000 ether);

        // vault holds 1000 of otherToken
        uint256 ownerBalBefore = otherToken.balanceOf(owner);
        uint256 vaultBalBefore = otherToken.balanceOf(address(vault));

        // onlyOwner can call
        vault.rescueStuckToken(address(otherToken));

        uint256 ownerBalAfter = otherToken.balanceOf(owner);
        uint256 vaultBalAfter = otherToken.balanceOf(address(vault));

        assertEq(ownerBalAfter - ownerBalBefore, vaultBalBefore, "Owner didn't receive the rescued tokens");
        assertEq(vaultBalAfter, 0, "Vault didn't send out the tokens");
    }

    function testRescueBaseTokenReverts() external {
        vm.expectRevert(bytes("Cannot rescue base token"));
        vault.rescueStuckToken(address(baseToken));
    }

    function getStrategies(address vaultAddress) internal view returns (address[] memory) {
        VaultMultiStrategy theVault = VaultMultiStrategy(vaultAddress);
        uint256 length = theVault.strategiesLength();
        address[] memory list = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            list[i] = theVault.strategies(i);
        }
        return list;
    }

    function testFuzzStrategySwitch(uint256 depositBeforeSwitch, uint256 depositAfterSwitch) external {
        depositBeforeSwitch = bound(depositBeforeSwitch, 1e1, 1e24);
        depositAfterSwitch = bound(depositAfterSwitch, 1e1, 1e24);

        address randomUser = makeRandomUser();

        // Mint tokens to the randomUser (if not enough already)
        uint256 totalMint = depositBeforeSwitch + depositAfterSwitch;
        baseToken.mint(randomUser, totalMint);

        // randomUser approves and deposits depositBeforeSwitch tokens.
        vm.startPrank(randomUser);
        baseToken.approve(address(vault), totalMint);
        vault.deposit(depositBeforeSwitch);
        vm.stopPrank();

        vm.prank(strategyManager);
        vault.addStrategy(address(strategyB));

        vm.prank(strategyManager);
        vault.switchStrategy(address(strategyB));

        vm.startPrank(randomUser);
        vault.deposit(depositAfterSwitch);
        vm.stopPrank();

        uint256 expectedFinalBalance = depositBeforeSwitch + depositAfterSwitch + 500 ether; // 500 ether from initial setup
        uint256 reportedFinalBalance = vault.balance();
        assertEq(reportedFinalBalance, expectedFinalBalance, "Final vault balance mismatch");

        assertEq(vault.activeStrategy(), address(strategyB), "Active strategy should be strategyB");

        uint256 stratABalance = strategyA.balanceOf();
        uint256 stratBBalance = strategyB.balanceOf();
        assertEq(stratABalance, 0, "Strategy A should have 0 balance after switch");
        assertEq(stratBBalance, expectedFinalBalance, "Strategy B should hold the combined vault balance");
    }
}
