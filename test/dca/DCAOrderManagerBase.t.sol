// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultStrict} from "../../src/yield/vault/VaultStrict.sol";
import {StrategyAaveV3Supply} from "../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {DCAOrderManagerV1} from "../../src/dca/DCAOrderManagerV1.sol";
import {BaseStrategy} from "../../src/yield/strategies/BaseStrategy.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockAavePool} from "./mock/strategy/aave/MockAavePool.t.sol";
import {MockAaveToken} from "./mock/strategy/aave/MockAaveToken.t.sol";
import {MockOnchainSwapper} from "./mock/strategy/aave/MockOnchainSwapper.t.sol";
import {MockAaveIncentives} from "./mock/strategy/aave/MockAaveIncentives.t.sol";
import {MockSwapRouterV3} from "./mock/swap-router/MockSwapRouterV3.t.sol";

contract DCAOrderManagerBaseTest is Test {
    address public owner = address(this);
    address public user1 = address(0x0001);
    address public user2 = address(0x0002);

    //strategy state
    address public strategyManager = address(this);
    address[] public rewards;
    uint256 platformFee = 0;
    uint256 lockDuration = 0 days;
    address public vault;
    VaultStrict vaultContract;
    StrategyAaveV3Supply strategy;
    MockERC20 baseToken;
    MockERC20 nativeToken;
    MockAavePool mockAavePool;
    MockAaveIncentives mockAaveIncentives;
    MockAaveToken mockAaveToken;

    //dca manager state
    DCAOrderManagerV1 dcaOrderManagerContract;
    address dcaOrderManager;
    address dcaOrderManagerExecutor = address(0x0003);

    MockSwapRouterV3 uniswapRouter = new MockSwapRouterV3();
    MockSwapRouterV3 pancakeRouter = new MockSwapRouterV3();

    function _deployVault() internal returns (VaultStrict) {
        VaultStrict implementation = new VaultStrict();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, bytes(""));

        return VaultStrict(address(proxy));
    }

    function _deployDCAOrderManager() internal returns (DCAOrderManagerV1) {
        DCAOrderManagerV1 implementation = new DCAOrderManagerV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, bytes(""));

        return DCAOrderManagerV1(payable(proxy));
    }

    function _deployStrategy() internal returns (StrategyAaveV3Supply) {
        StrategyAaveV3Supply strategyImpl = new StrategyAaveV3Supply();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(strategyImpl), owner, bytes(""));

        return StrategyAaveV3Supply(payable(proxy));
    }

    function setUpHelper() public virtual {
        baseToken = new MockERC20("WETH", "WETH");
        nativeToken = new MockERC20("ETH2", "ETH2");
        baseToken.mint(user1, 1_000 ether);
        baseToken.mint(user2, 1_000 ether);
        mockAaveIncentives = new MockAaveIncentives();
        MockOnchainSwapper mockOnchainSwapper = new MockOnchainSwapper();

        mockAaveToken = new MockAaveToken();
        mockAaveToken.initialize("Mock AToken", "MATK", address(baseToken), address(mockAaveIncentives));

        mockAavePool = new MockAavePool(address(mockAaveToken));

        mockAaveToken.setPool(address(mockAavePool));

        vaultContract = _deployVault();

        vault = address(vaultContract);

        dcaOrderManagerContract = _deployDCAOrderManager();

        dcaOrderManager = address(dcaOrderManagerContract);

        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addresses = BaseStrategy.Addresses({
            baseToken: address(baseToken),
            nativeToken: address(nativeToken),
            vault: vault,
            swapper: address(mockOnchainSwapper),
            strategyManager: strategyManager
        });

        strategy.initialize(address(mockAaveToken), false, rewards, addresses, platformFee, lockDuration);
        vaultContract.initialize(
            address(baseToken),
            address(strategy),
            strategyManager,
            dcaOrderManager,
            mockAaveToken.name(),
            mockAaveToken.symbol()
        );

        dcaOrderManagerContract.initialize(
            dcaOrderManagerExecutor, address(uniswapRouter), address(pancakeRouter), address(baseToken)
        );

        assertEq(vaultContract.activeStrategy(), address(strategy));
        assertEq(strategy.strategyName(), "Aave V3 supply");
    }
}
