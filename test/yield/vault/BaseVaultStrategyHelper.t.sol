// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultMultiStrategy} from "../../../src/yield/vault/Vault.sol";
import {MockStrategyV1} from "../mock/MockStrategyV1.sol";
import {BaseStrategy} from "../../../src/yield/strategies/BaseStrategy.sol";

abstract contract BaseVaultStrategyHelper is Test {
    address public owner = address(this);
    address public strategyManager = address(this);
    address[] public rewards;

    address user1 = address(0x1);
    address user2 = address(0x2);

    string constant NAME = "Vault Token";
    string constant SYMBOL = "vTOKEN";
    string constant STRATEGY_NAME = "vStrategy";

    function setUpHelper() public virtual {
        rewards.push(0x1111111111111111111111111111111111111111);
        rewards.push(0x2222222222222222222222222222222222222222);
    }

    function _deployVault() internal returns (VaultMultiStrategy) {
        VaultMultiStrategy implementation = new VaultMultiStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, bytes(""));
        return VaultMultiStrategy(address(proxy));
    }

    function _deployStrategy(address _vault, address _baseToken) internal returns (MockStrategyV1) {
        MockStrategyV1 strategyImpl = new MockStrategyV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(strategyImpl), owner, bytes(""));

        MockStrategyV1 strategy = MockStrategyV1(payable(proxy));

        BaseStrategy.Addresses memory addrs = BaseStrategy.Addresses({
            baseToken: _baseToken,
            nativeToken: address(0x1122),
            vault: _vault,
            swapper: address(0x1123),
            strategyManager: strategyManager
        });

        strategy.initialize(rewards, addrs, STRATEGY_NAME, 0, 1 days);

        return strategy;
    }

    function makeRandomUser() internal returns (address) {
        address randomUser =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))))));
        vm.assume(randomUser != owner && randomUser != strategyManager && randomUser != address(0));
        return randomUser;
    }
}
