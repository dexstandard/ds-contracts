// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/OrderManagerV1.sol";
import "./OrderManagerV1Testable.sol";
import {Test} from "forge-std/Test.sol";

contract OrderValidationTest is Test {
    OrderManagerV1Testable orderManager;

    function setUp() public {
        OrderManagerV1Testable implementation = new OrderManagerV1Testable();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        orderManager = OrderManagerV1Testable(payable(address(proxy)));
        orderManager.initialize(address(this), address(0x111), address(0x112));
    }

    function testValidOrder_success() public {
        uint256 ttl = 100;
        uint256 amountOutMin = 30;
        orderManager.validateOrder(ttl, amountOutMin);
    }

    function testExpiredOrder_fails() public {
        uint256 ttl = 0;
        uint256 amountOutMin = 30;

        vm.expectRevert(OrderExpired.selector);
        orderManager.validateOrder(ttl, amountOutMin);
    }

    function testFuzzValidOrder_success(
        uint256 ttl,
        uint256 amountOutMin
    ) public {
        // Constrain ttl to be in the future relative to block.timestamp
        ttl = block.timestamp + 1 + (ttl % (365 days));
        amountOutMin = bound(amountOutMin, 1, 10e18);
        orderManager.validateOrder(ttl, amountOutMin);
    }

    function testFuzzExpiredOrder_fails(
        address user,
        uint256 orderId,
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 ttl,
        uint256 nonce,
        uint256 amountOutMin
    ) public {
        // Constrain ttl to be in the past relative to block.timestamp
        ttl = ttl % block.timestamp;
        amountOutMin = bound(amountOutMin, 1, 10e18);

        vm.expectRevert(OrderExpired.selector);
        orderManager.validateOrder(ttl, amountOutMin);
    }

    function testInvalidAmountOutMin_fails() public {
        uint256 ttl = 100;
        uint256 amountOutMin = 0;
        // Expect revert due to invalid  amountOutMin
        vm.expectRevert(InvalidAmountOut.selector);
        orderManager.validateOrder(ttl, amountOutMin);
    }
}
