// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script, console} from "forge-std/Script.sol";
import {StrategyAaveV3Supply} from "../../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {BaseStrategy} from "../../../src/yield/strategies/BaseStrategy.sol";
import {YieldDeployerHelper} from "../../helpers/YieldDeployerHelper.s.sol";
import {VaultStrict} from "../../../src/yield/vault/VaultStrict.sol";

contract StrategyAaveV3SupplyUSDTWithVaultStrict is Script {
    function run() public {
        address owner = msg.sender;
        address strategyManager = msg.sender;
        address nativeToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB BNB
        address baseToken = 0x55d398326f99059fF775485246999027B3197955; // USDT BNB
        address aaveToken = 0xa9251ca9DE909CB71783723713B21E4233fbf1B1; // aUSDT BNB
        address dcaOrderManager = 0xa50a64C2a08048ddD3FC172192c1c5b934D0a44a; // arb DCA order manager (proxy)
        address onChainSwapper = address(0);
        address[] memory rewards;
        uint256 platformFee = 0;
        uint256 lockDuration = 0;

        vm.startBroadcast();

        YieldDeployerHelper yieldDeployerHelper = new YieldDeployerHelper();

        VaultStrict vaultStrictContract = yieldDeployerHelper.deployVaultStrict(owner);
        StrategyAaveV3Supply strategyContract = yieldDeployerHelper.deployStrategy(owner);

        yieldDeployerHelper.initializeStrategy(
            baseToken,
            nativeToken,
            address(vaultStrictContract),
            onChainSwapper,
            strategyManager,
            aaveToken,
            rewards,
            platformFee,
            lockDuration,
            strategyContract
        );

        yieldDeployerHelper.initializeVaultStrict(
            baseToken,
            address(strategyContract),
            strategyManager,
            dcaOrderManager,
            vaultStrictContract,
            "DexStandard USDT",
            "dUSDT",
            owner
        );

        vm.stopBroadcast();
    }
}
