// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseStrategy} from "../../../src/yield/strategies/BaseStrategy.sol";
import {BaseVaultStrategyHelper} from "./BaseVaultStrategyHelper.t.sol";

contract VaultMultiStrategyInitializationTest is BaseVaultStrategyHelper {
    address public constant baseToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // e.g., WETH on Arbitrum

    VaultMultiStrategy vault;
    MockStrategyV1 strategy;

    function setUp() external {
        setUpHelper();
    }

    function testInitialize() external {
        vault = _deployVault();

        strategy = _deployStrategy(address(vault), baseToken);

        vault.initialize(baseToken, address(strategy), strategyManager, NAME, SYMBOL);

        assertEq(vault.baseToken(), baseToken, "baseToken mismatch");
        assertEq(vault.activeStrategy(), address(strategy), "activeStrategy mismatch");
        assertEq(vault.strategyManager(), strategyManager, "strategyManager mismatch");
        assertEq(vault.name(), NAME, "Vault name mismatch");
        assertEq(vault.symbol(), SYMBOL, "Vault symbol mismatch");

        address[] memory vaultStrategies = getStrategies(address(vault));
        assertEq(vaultStrategies.length, 1, "Should have exactly 1 strategy stored");
        assertEq(vaultStrategies[0], address(strategy), "Wrong strategy stored");
    }

    function testInitializeZeroBaseTokenReverts() external {
        vault = _deployVault();
        strategy = _deployStrategy(address(vault), baseToken);

        vm.expectRevert(bytes("Invalid base token"));
        vault.initialize(address(0), address(strategy), strategyManager, NAME, SYMBOL);
    }

    function testInitializeZeroStrategyReverts() external {
        vault = _deployVault();

        vm.expectRevert(bytes("Invalid strategy"));
        vault.initialize(baseToken, address(0), strategyManager, NAME, SYMBOL);
    }

    function testInitializeZeroManagerReverts() external {
        vault = _deployVault();
        strategy = _deployStrategy(address(vault), baseToken);

        vm.expectRevert(bytes("Invalid strategy manager"));
        vault.initialize(baseToken, address(strategy), address(0), NAME, SYMBOL);
    }

    function testInitializeBaseTokenMismatchReverts() external {
        vault = _deployVault();

        MockStrategyV1 wrongStrategy = _deployStrategy(address(vault), address(0xDEADBEEF));

        vm.expectRevert(bytes("Strategy base token mismatch"));
        vault.initialize(baseToken, address(wrongStrategy), strategyManager, NAME, SYMBOL);
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
}
