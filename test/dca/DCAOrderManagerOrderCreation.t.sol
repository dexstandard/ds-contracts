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
import {DCAOrderManagerBaseTest} from "./DCAOrderManagerBase.t.sol";

contract DCAOrderManagerOrderCreationTest is DCAOrderManagerBaseTest {
    uint256 internal constant ORDER_ID = 1;
    uint256 internal constant AMOUNT_PER_ORDER = 10 ether;
    uint32 internal constant TOTAL_ORDERS = 5;
    uint256 internal constant INTERVAL = 1 days;

    function setUp() public {
        setUpHelper();
    }

    function expectCreateEmit(address user, uint256 orderId, uint256 totalTokenIn, address vault, uint256 shares)
        internal
    {
        vm.expectEmit(true, true, true, true);
        emit DCAOrderManagerV1.DCAOrderCreated(user, orderId, totalTokenIn, vault, shares);
    }

    function testCreateOrderWithNoVault() public {
        uint256 totalIn = AMOUNT_PER_ORDER * TOTAL_ORDERS;

        vm.startPrank(user1);
        baseToken.approve(address(dcaOrderManagerContract), totalIn);

        expectCreateEmit(user1, ORDER_ID, totalIn, address(0), 0);

        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(baseToken),
            address(nativeToken),
            totalIn,
            TOTAL_ORDERS,
            INTERVAL,
            address(0),
            block.timestamp
        );
        vm.stopPrank();

        (
            address _user,
            uint32 executedOrders,
            uint32 totalOrders,
            uint256 interval, // seconds between executions
            uint256 nextExecution, // timestamp when the next execution becomes valid
            address tokenIn,
            address tokenOut,
            , // vault address (0 if yield is disabled)
            uint256 sharesRemaining, // vault shares still owned by this order (0 if vault is null)
            uint256 amountInRemaining // token asset still owned by this order (0 if vault specified)
        ) = dcaOrderManagerContract.orders(ORDER_ID);

        assertEq(_user, user1, "user");
        assertEq(amountInRemaining, totalIn, "amountPerOrder");
        assertEq(executedOrders, 0, "executedOrders");
        assertEq(totalOrders, TOTAL_ORDERS, "totalOrders");
        assertEq(interval, INTERVAL, "interval");
        assertEq(nextExecution, block.timestamp, "nextExecution");
        assertEq(tokenIn, address(baseToken), "tokenIn");
        assertEq(tokenOut, address(nativeToken), "tokenOut");
        assertEq(sharesRemaining, 0, "sharesRemaining");

        assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), totalIn, "escrow");
    }

    function testCreateOrderWithVault() public {
        uint256 totalIn = AMOUNT_PER_ORDER * TOTAL_ORDERS;
        vm.startPrank(user1);
        baseToken.approve(vault, totalIn);

        uint256 shares = totalIn;

        expectCreateEmit(user1, ORDER_ID, totalIn, vault, shares);

        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(baseToken),
            address(nativeToken),
            totalIn,
            TOTAL_ORDERS,
            INTERVAL,
            address(vaultContract),
            block.timestamp
        );
        vm.stopPrank();

        (,,,,,,,, uint256 sharesRemaining,) = dcaOrderManagerContract.orders(ORDER_ID);

        assertEq(sharesRemaining, shares, "shares recorded");
        assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), 0, "no token escrow when vault");
    }

    function testCreateOrdersMultiple() public {
        {
            uint256 totalIn = AMOUNT_PER_ORDER * 5;
            vm.startPrank(user1);
            baseToken.approve(vault, totalIn);

            uint256 shares = totalIn;

            expectCreateEmit(user1, ORDER_ID, totalIn, vault, shares);

            dcaOrderManagerContract.createOrder(
                ORDER_ID,
                address(baseToken),
                address(nativeToken),
                totalIn,
                5,
                INTERVAL,
                address(vaultContract),
                block.timestamp
            );
            vm.stopPrank();

            (,,,,,,,, uint256 sharesRemaining,) = dcaOrderManagerContract.orders(ORDER_ID);

            assertEq(sharesRemaining, shares, "shares recorded");
            assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), 0, "no token escrow when vault");
        }

        {
            uint256 totalIn = AMOUNT_PER_ORDER * 10;
            vm.startPrank(user2);
            baseToken.approve(vault, totalIn);

            uint256 shares = totalIn;

            expectCreateEmit(user2, 2, totalIn, vault, shares);

            dcaOrderManagerContract.createOrder(
                2,
                address(baseToken),
                address(nativeToken),
                totalIn,
                10,
                INTERVAL,
                address(vaultContract),
                block.timestamp
            );
            vm.stopPrank();

            (,,,,,,,, uint256 sharesRemaining,) = dcaOrderManagerContract.orders(2);

            assertEq(sharesRemaining, shares, "shares recorded");
            assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), 0, "no token escrow when vault");
            assertEq(vaultContract.balance(), AMOUNT_PER_ORDER * 15, "vault balance is invalid");
        }

        {
            uint256 totalIn = AMOUNT_PER_ORDER * 10;
            vm.startPrank(user2);
            baseToken.approve(dcaOrderManager, totalIn);

            uint256 shares = 0;

            expectCreateEmit(user2, 3, totalIn, address(0), 0);

            dcaOrderManagerContract.createOrder(
                3, address(baseToken), address(nativeToken), totalIn, 10, INTERVAL, address(0), block.timestamp
            );
            vm.stopPrank();

            (,,,,,,,, uint256 sharesRemaining,) = dcaOrderManagerContract.orders(3);

            assertEq(sharesRemaining, shares, "shares recorded");
            assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), totalIn, "token escrow is not valid");
            assertEq(vaultContract.balance(), AMOUNT_PER_ORDER * 15, "vault balance is invalid");
        }
    }

    function testFuzzCreateOrder(
        uint256 orderId,
        uint256 amountPerOrder,
        uint32 totalOrders,
        uint256 interval,
        bool withVault
    ) public {
        vm.assume(orderId > 0);
        amountPerOrder = bound(amountPerOrder, 1, 1e21); // keep totals < ~1e23 to avoid overflow & gas OOG
        totalOrders = 10000000;
        interval = bound(interval, 1, 30 days);

        amountPerOrder = amountPerOrder;
        totalOrders = totalOrders;
        uint256 totalIn = amountPerOrder * totalOrders; // safe: ≤ 1e21 * 50

        baseToken.mint(user1, totalIn);

        vm.startPrank(user1);
        baseToken.approve(address(dcaOrderManagerContract), totalIn);

        address vaultAddr = withVault ? address(vaultContract) : address(0);

        if (withVault) {
            baseToken.approve(vaultAddr, totalIn);
        }

        (address _user,,,,,,,,,) = dcaOrderManagerContract.orders(ORDER_ID);

        bool shouldRevert = _user != address(0);
        if (shouldRevert) {
            vm.expectRevert(abi.encodeWithSelector(DCAOrderManagerV1.OrderExists.selector, orderId));
        }

        dcaOrderManagerContract.createOrder(
            orderId,
            address(baseToken),
            address(nativeToken),
            totalIn,
            totalOrders,
            interval,
            vaultAddr,
            block.timestamp
        );
        vm.stopPrank();

        if (shouldRevert) return; // no invariants to check

        /**
         * Invariants **
         */
        (
            address user,
            uint32 executed,
            uint32 total,
            uint256 inter, // seconds between executions
            uint256 next, // timestamp when the next execution becomes valid
            ,
            ,
            , // vault address (0 if yield is disabled)
            uint256 shares, // vault shares still owned by this order (0 if vault is null)
            uint256 amountInRemaining // token asset still owned by this order (0 if vault specified)
        ) = dcaOrderManagerContract.orders(orderId);

        assertEq(user, user1, "owner mismatch");
        assertEq(executed, 0, "executedOrders should start at 0");
        assertEq(total, totalOrders, "totalOrders mismatch");
        assertEq(inter, interval, "interval mismatch");
        assertEq(next, block.timestamp, "nextExecution should equal now");

        if (withVault) {
            assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), 0, "manager should not hold tokens");
            assertGt(shares, 0, "non-zero vault shares recorded");
            assertEq(amountInRemaining, 0, "amountPerOrder mismatch");
        } else {
            assertEq(amountInRemaining, totalIn, "amountPerOrder mismatch");
            assertEq(shares, 0, "shares should be zero without vault");
            assertEq(baseToken.balanceOf(address(dcaOrderManagerContract)), totalIn, "manager escrow mismatch");
        }
    }

    function testCreateOrderRevertsOrderExists() public {
        vm.startPrank(user1);
        baseToken.approve(address(dcaOrderManagerContract), 100 ether);
        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(baseToken),
            address(nativeToken),
            AMOUNT_PER_ORDER,
            TOTAL_ORDERS,
            INTERVAL,
            address(0),
            block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(DCAOrderManagerV1.OrderExists.selector, ORDER_ID));
        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(baseToken),
            address(nativeToken),
            AMOUNT_PER_ORDER,
            TOTAL_ORDERS,
            INTERVAL,
            address(0),
            block.timestamp
        );
        vm.stopPrank();
    }

    function testCreateOrderRevertsInvalidOrderSizeDetailsZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(DCAOrderManagerV1.InvalidOrderSizeDetails.selector);
        dcaOrderManagerContract.createOrder(
            ORDER_ID, address(baseToken), address(nativeToken), 0, TOTAL_ORDERS, INTERVAL, address(0), block.timestamp
        );
    }

    function testCreateOrderRevertsInvalidOrderSizeDetailsZeroTotal() public {
        vm.prank(user1);
        vm.expectRevert(DCAOrderManagerV1.InvalidOrderSizeDetails.selector);
        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(baseToken),
            address(nativeToken),
            AMOUNT_PER_ORDER,
            0,
            INTERVAL,
            address(0),
            block.timestamp
        );
    }

    function testCreateOrderRevertsInvalidTokenInForVault() public {
        vm.prank(user1);
        vm.expectRevert(DCAOrderManagerV1.InvalidTokenInForVault.selector);
        dcaOrderManagerContract.createOrder(
            ORDER_ID,
            address(nativeToken),
            address(baseToken),
            AMOUNT_PER_ORDER,
            TOTAL_ORDERS,
            INTERVAL,
            address(vaultContract),
            block.timestamp
        );
    }
}
