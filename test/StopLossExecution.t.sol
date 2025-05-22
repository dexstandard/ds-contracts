// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../src/OrderManagerV1.sol";
import "./mock/MockUniswapRouterV2.sol";
import "forge-std/console.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

contract StopLossExecutionTest is Test {
    OrderManagerV1 orderManager;
    MockUniswapRouterV2 mockRouter;
    MockERC20 weth = new MockERC20("wrappedETH", "WETH");
    MockERC20 tokenIn = new MockERC20("TokenIn", "TIN");
    MockERC20 tokenOut = new MockERC20("TokenOut", "TOUT");
    address user = vm.addr(1);

    function setUp() public {
        mockRouter = new MockUniswapRouterV2();
        weth.mint(address(mockRouter), 1_000_000 ether);
        tokenOut.mint(address(mockRouter), 1_000_000 ether);
        vm.deal(address(weth), 1_000_000 ether);

        OrderManagerV1 implementation = new OrderManagerV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            ""
        );
        orderManager = OrderManagerV1(payable(address(proxy)));
        orderManager.initialize(
            address(this),
            address(mockRouter),
            address(mockRouter),
            address(mockRouter),
            address(weth)
        );
    }

    function createDigest(StopMarketOrder memory order) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                orderManager.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        orderManager.ORDER_TYPEHASH(),
                        order.user,
                        order.orderId,
                        order.amountIn,
                        order.tokenIn,
                        order.tokenOut,
                        order.ttl,
                        order.amountOutMin,
                        order.takeProfitOutMin,
                        order.stopLossOutMin
                    )
                )
            )
        );
    }

    function prepareTokenForUser(
        address _user,
        MockERC20 token,
        uint256 amount
    ) internal {
        token.mint(_user, amount);
        vm.prank(_user);
        token.approve(address(orderManager), amount);
        vm.stopPrank();
    }

    /**
     * @dev Opens a StopMarketOrder so that we can later execute a stop-loss on it.
     */
    function prepareOrderForStopLoss() internal returns (StopMarketOrder memory) {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 stopLossOutMin = 0.7 ether;
        uint256 fee = 0.2 ether;

        return prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee,
            tokenOut
        );
    }

    function prepareOrderForStopLoss(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee
    ) internal returns (StopMarketOrder memory) {
        return prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee,
            tokenOut
        );
    }

    function prepareOrderForStopLoss(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee,
        MockERC20 _tokenOut
    ) internal returns (StopMarketOrder memory) {
        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(_tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0, // takeProfit not relevant here
            stopLossOutMin: stopLossOutMin
        });

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(tokenIn), address(_tokenOut), amountIn - fee, amountOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenIn), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);
        return order;
    }

    function testExecuteStopLossOrder_success() public {
        uint256 fee = 0.2 ether;
        StopMarketOrder memory order = prepareOrderForStopLoss();

        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(order.orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenOut),
            address(tokenIn),
            openAmountOut - fee,
            order.stopLossOutMin
        );
        mockRouter.expectSwap(address(orderManager), address(tokenOut), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));
        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.StopLossExecuted(
            address(this),
            user,
            order.orderId,
            order.stopLossOutMin,
            address(tokenIn),
            fee
        );

        uint256 userBalanceBefore = tokenIn.balanceOf(user);
        orderManager.executeStopLoss(order, swapData, swapData, v, r, s, 0);
        uint256 userBalanceAfter = tokenIn.balanceOf(user);

        uint256 actualAmountOut = userBalanceAfter - userBalanceBefore;
        assertEq(
            actualAmountOut,
            order.stopLossOutMin,
            "StopLoss: final user balance does not match expected out"
        );
    }

    function testFuzzExecuteStopLossOrder_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(stopLossOutMin > 0 && stopLossOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee
        );

        (uint256 openAmountOut, ) = orderManager.getAmountOut(order.orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(tokenOut), address(tokenIn), openAmountOut - fee, stopLossOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenOut), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));
        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.StopLossExecuted(
            address(this),
            user,
            order.orderId,
            stopLossOutMin,
            address(tokenIn),
            fee
        );

        uint256 userBalanceBefore = tokenIn.balanceOf(user);
        orderManager.executeStopLoss(order, swapData, swapData, v, r, s, 0);
        uint256 userBalanceAfter = tokenIn.balanceOf(user);

        assertEq(
            userBalanceAfter - userBalanceBefore,
            stopLossOutMin,
            "StopLoss: user final balance mismatch"
        );
    }

    function testExecuteStopLossOrder_tokenInWeth_success() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 stopLossOutMin = 0.7 ether;
        uint256 fee = 0.2 ether;

        StopMarketOrder memory order = prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee,
            weth
        );

        (uint256 openAmountOut, ) = orderManager.getAmountOut(orderId);

        vm.prank(user);
        weth.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(weth), address(tokenIn), openAmountOut - fee, stopLossOutMin);

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.StopLossExecuted(
            address(this),
            user,
            orderId,
            stopLossOutMin,
            address(tokenIn),
            fee
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        uint256 executorBalanceBefore = address(this).balance;
        orderManager.executeStopLoss(order, swapData, swapData, v2, r2, s2, 0);

        assertEq(
            address(this).balance - executorBalanceBefore,
            fee,
            "StopLoss: mismatch in final executor native fee"
        );
    }

    function testFuzzExecuteStopLossOrder_tokenInWeth_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(stopLossOutMin > 0 && stopLossOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee,
            weth
        );

        (uint256 openAmountOut, ) = orderManager.getAmountOut(orderId);

        vm.prank(user);
        weth.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(weth), address(tokenIn), openAmountOut - fee, stopLossOutMin);

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.StopLossExecuted(
            address(this),
            user,
            orderId,
            stopLossOutMin,
            address(tokenIn),
            fee
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        uint256 executorBalanceBefore = address(this).balance;
        orderManager.executeStopLoss(order, swapData, swapData, v2, r2, s2, 0);

        assertEq(
            address(this).balance - executorBalanceBefore,
            fee,
            "StopLoss: mismatch in final executor native fee"
        );
    }

    function testFuzzExecuteStopLoss_emptyFeeSwapData_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(stopLossOutMin > 0 && stopLossOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee
        );

        (uint256 openAmountOut, ) = orderManager.getAmountOut(order.orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenOut),
            address(tokenIn),
            openAmountOut, // no fee subtracted
            stopLossOutMin
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        bytes memory emptySwapData = "";

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.StopLossExecuted(
            address(this),
            user,
            orderId,
            stopLossOutMin,
            address(tokenIn),
            0
        );

        uint256 executorBalanceBefore = address(this).balance;
        orderManager.executeStopLoss(order, swapData, emptySwapData, v, r, s, 0);

        assertEq(
            address(this).balance - executorBalanceBefore,
            0,
            "StopLoss: fee should be zero with empty feeSwapData"
        );
    }

    function testFuzzExecuteStopLossOrder_amountOutMismatch_reverted(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 stopLossOutMin,
        uint256 fee,
        uint256 mismatchedAmountOut
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(stopLossOutMin > 0 && stopLossOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForStopLoss(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            stopLossOutMin,
            fee
        );

        (uint256 openAmountOut, ) = orderManager.getAmountOut(orderId);
        vm.assume(mismatchedAmountOut > 0 && mismatchedAmountOut < stopLossOutMin);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenOut),
            address(tokenIn),
            openAmountOut - fee,
            mismatchedAmountOut
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        bytes memory emptySwapData = "";

        vm.expectRevert(
            abi.encodeWithSelector(
                AmountOutTooLow.selector,
                user,
                orderId,
                mismatchedAmountOut,
                stopLossOutMin
            )
        );
        orderManager.executeStopLoss(order, swapData, emptySwapData, v, r, s, 0);
    }

    function testExecuteStopLossOrder_openOrderIsNotExecuted_reverted() public {
        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: 1234, // random
            amountIn: 1 ether,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: block.timestamp + 1 hours,
            amountOutMin: 1e17,
            takeProfitOutMin: 0, // not relevant
            stopLossOutMin: 1e17
        });

        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        vm.expectRevert(abi.encodeWithSelector(OpenOrderNotFound.selector, order.orderId));

        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeStopLoss(order, swapData, swapData, v, r, s, 0);
    }

    receive() external payable {}
}
