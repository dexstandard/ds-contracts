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
import {DCAOrderManagerBaseTest} from "./DCAOrderManagerBase.t.sol";

contract DCAOrderManagerOrderCancellationTest is DCAOrderManagerBaseTest {
    uint256 internal constant AMOUNT_PER_ORDER = 10 ether;
    uint256 internal constant INTERVAL = 1 days;
    uint24 internal constant FEE_TIER = 3000; // 0.3%

    function setUp() public {
        setUpHelper();
    }

    function testExecuteOrderSuccessfulWithoutVault() public {
        uint256 totalIn = AMOUNT_PER_ORDER * 5;
        vm.startPrank(user1);
        baseToken.approve(address(dcaOrderManagerContract), totalIn);
        dcaOrderManagerContract.createOrder(
            1,
            address(baseToken),
            address(nativeToken),
            totalIn,
            5,
            INTERVAL,
            address(0), // no vault
            block.timestamp
        );

        uint256 balBefore = baseToken.balanceOf(user1);

        dcaOrderManagerContract.cancelOrder(1);
        vm.stopPrank();

        uint256 balAfter = baseToken.balanceOf(user1);
        assertEq(balAfter - balBefore, totalIn, "refunded exact leftover");
        assertTrue(dcaOrderManagerContract.orderClosed(1));
    }

    function testExecuteOrderSuccessfulWithVault() public {
        uint256 totalIn = AMOUNT_PER_ORDER * 5;
        vm.startPrank(user1);
        baseToken.approve(vault, totalIn);
        dcaOrderManagerContract.createOrder(
            1, address(baseToken), address(nativeToken), totalIn, 5, INTERVAL, vault, block.timestamp
        );

        uint256 balBefore = baseToken.balanceOf(user1);

        dcaOrderManagerContract.cancelOrder(1);
        vm.stopPrank();

        uint256 balAfter = baseToken.balanceOf(user1);
        assertEq(balAfter - balBefore, totalIn, "refunded exact leftover");
        assertTrue(dcaOrderManagerContract.orderClosed(1));
    }
}
