// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../src/OrderManagerV1.sol";
import "./mock/MockUniswapRouterV2.sol";
import "forge-std/console.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

contract TakeProfitExecutionTest is Test {
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
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        orderManager = OrderManagerV1(payable(address(proxy)));
        orderManager.initialize(address(this), address(mockRouter), address(weth));
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

    function prepareTokenForUser(address user, MockERC20 token, uint256 amount) internal {
        token.mint(address(user), amount);
        vm.prank(user);
        token.approve(address(orderManager), amount);
        vm.stopPrank();
    }

    function prepareOrderForTakeProfit() internal returns(StopMarketOrder memory) {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 takeProfitOutMin = 0.9 ether;
        uint256 fee = 0.2 ether;

        return prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee,
            tokenOut
        );
    }

    function prepareOrderForTakeProfit(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee
    ) internal returns (StopMarketOrder memory) {
        return prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee,
            tokenOut
        );
    }

    function prepareOrderForTakeProfit(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee,
        MockERC20 tokenOut
    ) internal returns (StopMarketOrder memory) {
        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: takeProfitOutMin,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), amountIn - fee, amountOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenIn), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeOrder(order, swapData, swapData, v, r, s);
        return order;
    }

    function testExecuteTakeProfitOrder_success() public {
        uint256 fee = 0.2 ether;
        StopMarketOrder memory order = prepareOrderForTakeProfit();
        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(order.orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenOut), address(tokenIn), openAmountOut - fee, order.takeProfitOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenOut), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.TakeProfitExecuted(
            address(this),
            user,
            order.orderId,
            order.takeProfitOutMin,
            address(tokenIn),
            fee
        );

        uint256 userBalanceBefore = tokenIn.balanceOf(user);
        orderManager.executeTakeProfit(order, swapData, swapData, v, r, s);
        uint256 actualAmountOut = tokenIn.balanceOf(user) - userBalanceBefore;

        assertEq(tokenIn.balanceOf(user),order.takeProfitOutMin, "amountOut mismatch");
        assertEq(actualAmountOut, order.takeProfitOutMin, "amountsOut mismatch");
    }

    function testFuzzExecuteTakeProfitOrder_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(takeProfitOutMin > 0 && takeProfitOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee
        );
        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(order.orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenOut), address(tokenIn), openAmountOut - fee, order.takeProfitOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenOut), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.TakeProfitExecuted(
            address(this),
            user,
            order.orderId,
            order.takeProfitOutMin,
            address(tokenIn),
            fee
        );

        uint256 userBalanceBefore = tokenIn.balanceOf(user);
        orderManager.executeTakeProfit(order, swapData, swapData, v, r, s);
        uint256 actualAmountOut = tokenIn.balanceOf(user) - userBalanceBefore;

        assertEq(tokenIn.balanceOf(user),order.takeProfitOutMin, "amountOut mismatch");
        assertEq(actualAmountOut, order.takeProfitOutMin, "amountsOut mismatch");
    }


    function testExecuteTakeProfitOrder_tokenInWeth_success() public {
        // open order
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 takeProfitOutMin = 0.9 ether;
        uint256 fee = 0.2 ether;

        StopMarketOrder memory order = prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee,
            weth
        );

        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(orderId);

        vm.prank(user);
        weth.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user, address(weth), address(tokenIn), openAmountOut - fee, takeProfitOutMin
        );

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.TakeProfitExecuted(
            address(this),
            user,
            orderId,
            takeProfitOutMin,
            address(tokenIn),
            fee
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        uint256 executorBalanceBefore = address(this).balance;
        orderManager.executeTakeProfit(order, swapData, swapData, v2, r2, s2);
        assertEq(address(this).balance - executorBalanceBefore, fee, "fee mismatch");
    }


    function testFuzzExecuteTakeProfitOrder_tokenInWeth_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(takeProfitOutMin > 0 && takeProfitOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee,
            weth
        );

        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(orderId);

        vm.prank(user);
        weth.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user, address(weth), address(tokenIn), openAmountOut - fee, takeProfitOutMin
        );

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.TakeProfitExecuted(
            address(this),
            user,
            orderId,
            takeProfitOutMin,
            address(tokenIn),
            fee
        );

        bytes memory swapData = abi.encodePacked(uint256(1));
        uint256 executorBalanceBefore = address(this).balance;
        orderManager.executeTakeProfit(order, swapData, swapData, v2, r2, s2);
        assertEq(address(this).balance - executorBalanceBefore, fee, "fee mismatch");
    }

    function testFuzzExecuteTakeProfit_emptyFeeSwapData_success(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(takeProfitOutMin > 0 && takeProfitOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee
        );

        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(orderId);

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenOut),
            address(tokenIn),
            openAmountOut,
            takeProfitOutMin
        );
        bytes memory emptySwapData = "";
        bytes memory swapData = abi.encodePacked(uint256(1));
        uint256 executorBalanceBefore = address(this).balance;

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.TakeProfitExecuted(
            address(this),
            user,
            orderId,
            takeProfitOutMin,
            address(tokenIn),
            0
        );
        orderManager.executeTakeProfit(order, swapData, emptySwapData, v2, r2, s2);
        assertEq(address(this).balance - executorBalanceBefore, 0, "fee mismatch");
    }


    function testFuzzExecuteTakeProfitOrder_amountOutMismatch_reverted(
        uint256 orderId,
        uint256 amountIn,
        uint256 ttl,
        uint256 amountOutMin,
        uint256 takeProfitOutMin,
        uint256 fee,
        uint256 mismatchedAmountOut
    ) public {
        vm.assume(orderId >= 0);
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(ttl > block.timestamp);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(takeProfitOutMin > 0 && takeProfitOutMin <= amountOutMin);
        vm.assume(fee > 0 && fee < amountOutMin);

        StopMarketOrder memory order = prepareOrderForTakeProfit(
            orderId,
            amountIn,
            ttl,
            amountOutMin,
            takeProfitOutMin,
            fee
        );

        (uint256 openAmountOut, address openTokenOut) = orderManager.getAmountOut(orderId);
        vm.assume(mismatchedAmountOut > 0 && mismatchedAmountOut < order.takeProfitOutMin); // Ensure mismatch occurs

        vm.prank(user);
        tokenOut.approve(address(orderManager), openAmountOut);
        vm.stopPrank();

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenOut),
            address(tokenIn),
            openAmountOut - fee,
            mismatchedAmountOut // Mismatched amount out
        );
        bytes memory emptySwapData = "";
        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(AmountOutTooLow.selector, user, orderId, mismatchedAmountOut, takeProfitOutMin)
        );
        orderManager.executeTakeProfit(order, swapData, emptySwapData, v2, r2, s2);
    }

    function testExecuteTakeProfitOrder_openOrderIsNotExecuted_reverted() public {

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: 1,
            amountIn: 1000,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: block.timestamp + 1 hours,
            amountOutMin: 1000,
            takeProfitOutMin: 1000,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, digest);

        vm.expectRevert(abi.encodeWithSelector(OpenOrderNotFound.selector, 1));

        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeTakeProfit(order, swapData, swapData, v2, r2, s2);
    }

    receive() external payable {}
}
