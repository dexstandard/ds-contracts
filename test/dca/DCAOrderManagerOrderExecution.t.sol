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

contract DCAOrderManagerOrderExecutionTest is DCAOrderManagerBaseTest {
    uint256 internal constant AMOUNT_PER_ORDER = 10 ether;
    uint256 internal constant INTERVAL = 1 days;
    uint24 internal constant FEE_TIER = 3000; // 0.3%

    function setUp() public {
        setUpHelper();
    }

    function testOnlyExecutor() public {
        uint256 totalIn = AMOUNT_PER_ORDER * 5;

        vm.startPrank(user1);
        baseToken.approve(address(dcaOrderManagerContract), totalIn);

        dcaOrderManagerContract.createOrder(
            1, address(baseToken), address(nativeToken), totalIn, 5, INTERVAL, address(0), block.timestamp
        );

        vm.expectRevert(DCAOrderManagerV1.UnauthorizedExecutor.selector);
        dcaOrderManagerContract.executeOrder(
            1, _singleHopPath(address(baseToken), address(nativeToken)), 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap
        );
    }

    function testExecuteOrderSuccessfulWithoutVault() public {
        nativeToken.mint(address(uniswapRouter), 10 ether);

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
        vm.stopPrank();

        uniswapRouter.expectExactInput(user1, address(baseToken), address(nativeToken), AMOUNT_PER_ORDER, 10 ether);

        vm.startPrank(dcaOrderManagerExecutor);

        vm.expectEmit(true, true, true, true);
        emit DCAOrderManagerV1.DCAOrderExecuted(
            dcaOrderManagerExecutor, user1, 1, 1, AMOUNT_PER_ORDER, 10 ether, 0 ether
        );

        dcaOrderManagerContract.executeOrder(
            1, _singleHopPath(address(baseToken), address(nativeToken)), 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap
        );
        vm.stopPrank();

        (, uint32 executed,,, uint256 nextExec,,,, uint256 sharesRem,) = dcaOrderManagerContract.orders(1);

        assertEq(executed, 1, "executedOrders increment");
        assertEq(nextExec, block.timestamp + INTERVAL, "nextExecution advanced");
        assertEq(sharesRem, 0, "no vault shares");
        assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), totalIn - AMOUNT_PER_ORDER, "escrow reduced");

        assertEq(uniswapRouter.active(), 1, "mock router used once");
    }

    function testExecuteOrderSuccessfulWithVault() public {
        nativeToken.mint(address(uniswapRouter), 10 ether);

        uint256 totalIn = AMOUNT_PER_ORDER * 5;
        vm.startPrank(user1);
        baseToken.approve(address(vault), totalIn);
        dcaOrderManagerContract.createOrder(
            1, address(baseToken), address(nativeToken), totalIn, 5, INTERVAL, vault, block.timestamp
        );
        vm.stopPrank();

        (,,,,,,,, uint256 sharesBefore,) = dcaOrderManagerContract.orders(1);

        uniswapRouter.expectExactInput(user1, address(baseToken), address(nativeToken), AMOUNT_PER_ORDER, 10 ether);

        vm.startPrank(dcaOrderManagerExecutor);

        vm.expectEmit(true, true, true, true);
        emit DCAOrderManagerV1.DCAOrderExecuted(
            dcaOrderManagerExecutor, user1, 1, 1, AMOUNT_PER_ORDER, 10 ether, 0 ether
        );

        dcaOrderManagerContract.executeOrder(
            1, _singleHopPath(address(baseToken), address(nativeToken)), 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap
        );
        vm.stopPrank();

        (, uint32 executedOrders,,, uint256 nextExecution,,,, uint256 sharesRemaining,) =
            dcaOrderManagerContract.orders(1);

        assertEq(executedOrders, 1, "executedOrders increment");
        assertEq(nextExecution, block.timestamp + INTERVAL, "nextExecution advanced");
        assertLt(sharesRemaining, sharesBefore, "shares should burn");
        assertEq(sharesRemaining, totalIn - AMOUNT_PER_ORDER, "shares should burn");
        assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), 0, "escrow not reduced");

        assertEq(uniswapRouter.active(), 1, "mock router used once");
    }

    function testNotReadyRevert() public {
        nativeToken.mint(address(uniswapRouter), 20 ether);

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
        vm.stopPrank();

        uniswapRouter.expectExactInput(user1, address(baseToken), address(nativeToken), AMOUNT_PER_ORDER, 10 ether);

        vm.prank(dcaOrderManagerExecutor);
        dcaOrderManagerContract.executeOrder(
            1, _singleHopPath(address(baseToken), address(nativeToken)), 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap
        );

        vm.prank(dcaOrderManagerExecutor);
        vm.expectRevert(abi.encodeWithSelector(DCAOrderManagerV1.NotReady.selector, 1, INTERVAL + 1));
        dcaOrderManagerContract.executeOrder(
            1, _singleHopPath(address(baseToken), address(nativeToken)), 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap
        );
    }

    function testAllOrdersExecutedAndClosed() public {
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
        vm.stopPrank();

        for (uint8 i = 0; i < 5; i++) {
            uniswapRouter.expectExactInput(user1, address(baseToken), address(nativeToken), AMOUNT_PER_ORDER, 10 ether);

            nativeToken.mint(address(uniswapRouter), 10 ether);

            vm.warp(block.timestamp + INTERVAL * i);
            vm.prank(dcaOrderManagerExecutor);
            dcaOrderManagerContract.executeOrder(
                1,
                _singleHopPath(address(baseToken), address(nativeToken)),
                0,
                "",
                0,
                0,
                DCAOrderManagerV1.DexEnum.Uniswap
            );
        }

        assertTrue(dcaOrderManagerContract.orderClosed(1), "flag set");

        // try execute again
        vm.prank(dcaOrderManagerExecutor);
        vm.expectRevert(abi.encodeWithSelector(DCAOrderManagerV1.AllOrdersExecuted.selector, 1));
        dcaOrderManagerContract.executeOrder(1, "", 0, "", 0, 0, DCAOrderManagerV1.DexEnum.Uniswap);
    }

    function _singleHopPath(address _tokenIn, address _tokenOut) internal pure returns (bytes memory) {
        return abi.encodePacked(_tokenIn, uint24(FEE_TIER), _tokenOut);
    }
}
