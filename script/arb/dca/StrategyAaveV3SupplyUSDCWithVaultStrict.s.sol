// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script, console} from "forge-std/Script.sol";
import {StrategyAaveV3Supply} from "../../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {BaseStrategy} from "../../../src/yield/strategies/BaseStrategy.sol";
import {YieldDeployerHelper} from "../../helpers/YieldDeployerHelper.s.sol";
import {VaultStrict} from "../../../src/yield/vault/VaultStrict.sol";

contract StrategyAaveV3SupplyUSDCWithVaultStrict is Script {
    function run() public {
        address owner = msg.sender;
        address strategyManager = msg.sender;
        address nativeToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH Arbitrum
        address baseToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC Arbitrum
        address aaveToken = 0x724dc807b04555b71ed48a6896b6F41593b8C637; // aUSDC Arbitrum
        address dcaOrderManager = 0x515C9516BDcD2FAE1856570414964e8aD885410E; // arb DCA order manager (proxy)
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
            "DexStandard USDC",
            "dUSDC",
            owner
        );

        vm.stopBroadcast();
    }
}
