// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultMultiStrategy} from "../../../../src/yield/vault/Vault.sol";

import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockStrategyV1} from "../../mock/MockStrategyV1.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";

abstract contract BaseStrategyHelper is Test {
    address public owner = address(this);
    address public strategyManager = address(this);
    address[] public rewards;
    address public reward1 = address(0x1111111111111111111111111111111111111111);
    address public reward2 = address(0x2222222222222222222222222222222222222222);

    MockERC20 baseToken = new MockERC20("WETH", "WETH");
    MockERC20 nativeToken = new MockERC20("Native", "NT");
    address swapper = address(0x12);

    address user1 = address(0x1);
    address user2 = address(0x2);

    string constant NAME = "Vault Token";
    string constant SYMBOL = "vTOKEN";
    string constant STRATEGY_NAME = "vStrategy";

    function setUpHelper() public virtual {
        rewards.push(reward1);
        rewards.push(reward2);
    }

    function _deployVault() internal returns (VaultMultiStrategy) {
        VaultMultiStrategy implementation = new VaultMultiStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, bytes(""));

        return VaultMultiStrategy(address(proxy));
    }

    function _deployStrategy() internal returns (MockStrategyV1) {
        MockStrategyV1 strategyImpl = new MockStrategyV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(strategyImpl), owner, bytes(""));

        MockStrategyV1 strategy = MockStrategyV1(payable(proxy));

        return strategy;
    }

    function makeRandomUser() internal returns (address) {
        address randomUser =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))))));
        vm.assume(randomUser != owner && randomUser != strategyManager && randomUser != address(0));
        return randomUser;
    }

    function _getStrategyDeployAddresses(address _vault) internal returns (BaseStrategy.Addresses memory addresses) {
        BaseStrategy.Addresses memory addresses = BaseStrategy.Addresses({
            baseToken: address(baseToken),
            nativeToken: address(nativeToken),
            vault: _vault,
            swapper: swapper,
            strategyManager: strategyManager
        });

        return addresses;
    }
}
