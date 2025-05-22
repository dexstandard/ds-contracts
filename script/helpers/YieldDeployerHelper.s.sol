// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script} from "forge-std/Script.sol";
import {StrategyAaveV3Supply} from "../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {BaseStrategy} from "../../src/yield/strategies/BaseStrategy.sol";
import {VaultStrict} from "../../src/yield/vault/VaultStrict.sol";

import {Script, console} from "forge-std/Script.sol";

contract YieldDeployerHelper is Script {
    /**
     * Deploys the strategy implementation and proxy without initialization
     * @param owner address
     */
    function deployStrategy(address owner) public returns (StrategyAaveV3Supply strategy) {
        StrategyAaveV3Supply implementation = new StrategyAaveV3Supply();

        bytes memory initData = bytes("");

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, initData);

        bytes memory constructorArgs = abi.encode(address(implementation), owner, initData);

        console.log("StrategyAaveV3Supply implementation deployed at:", address(implementation));
        console.log("StrategyAaveV3Supply proxy deployed at:", address(proxy));
        console.log("Constructor args (hex):");
        console.logBytes(constructorArgs);

        return StrategyAaveV3Supply(payable(proxy));
    }

    /**
     * @dev Initialize strategy (proxy) with all state variables
     * @param baseToken - base token of the strategy
     * @param nativeToken - native token of chain
     * @param vault - vault address
     * @param onChainSwapper - on chain swapper with oracle
     * @param strategyManager - manager
     * @param aaveToken - wrapped base token
     * @param rewards - array of strategy rewards
     * @param platformFee - fee of the platform
     * @param lockDuration - withdrawal lock
     * @param strategy - strategy contract
     */
    function initializeStrategy(
        address baseToken,
        address nativeToken,
        address vault,
        address onChainSwapper,
        address strategyManager,
        address aaveToken,
        address[] calldata rewards,
        uint256 platformFee,
        uint256 lockDuration,
        StrategyAaveV3Supply strategy
    ) public {
        BaseStrategy.Addresses memory addresses = BaseStrategy.Addresses({
            baseToken: baseToken,
            nativeToken: nativeToken,
            vault: vault,
            swapper: onChainSwapper,
            strategyManager: strategyManager
        });

        strategy.initialize(address(aaveToken), false, rewards, addresses, platformFee, lockDuration);
    }

    /**
     * Deploys the vault strict implementation and proxy without initialization
     * @param owner address
     */
    function deployVaultStrict(address owner) public returns (VaultStrict vault) {
        VaultStrict implementation = new VaultStrict();

        bytes memory initData = bytes("");

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, initData);

        bytes memory constructorArgs = abi.encode(address(implementation), owner, initData);

        console.log("VaultStrict implementation deployed at:", address(implementation));
        console.log("VaultStrict proxy deployed at:", address(proxy));
        console.log("Constructor args (hex):");
        console.logBytes(constructorArgs);

        return VaultStrict(address(proxy));
    }

    /**
     * @dev Initialize the vault with state variables.
     * @param baseToken Address of the token that the vault and strategies will handle.
     * @param strategy The address of the strategy.
     * @param strategyManager The address allowed to manage strategies.
     * @param name The name of the vault token (for ERC20).
     * @param symbol The symbol of the vault token (for ERC20).
     * @param owner address
     */
    function initializeVaultStrict(
        address baseToken,
        address strategy,
        address strategyManager,
        address dcaOrderManager,
        VaultStrict vault,
        string memory name,
        string memory symbol,
        address owner
    ) public {
        vault.initialize(baseToken, strategy, strategyManager, dcaOrderManager, name, symbol);
        vault.transferOwnership(owner);
    }
}
