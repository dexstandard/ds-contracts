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
        address nativeToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH Arbitrum
        address baseToken = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT Arbitrum
        address aaveToken = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620; // aUSDT Arbitrum
        address dcaOrderManager = 0xc226F471691e503163C85c482B54a23ba53b31C1; // arb DCA order manager (proxy)
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
