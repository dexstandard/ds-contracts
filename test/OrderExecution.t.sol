// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../src/OrderManagerV1.sol";
import "./mock/MockUniswapRouterV2.sol";
import "forge-std/console.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

contract OrderExecutionTest is Test {
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

    function prepareTokenForUser(address user, MockERC20 token, uint256 amount) internal {
        token.mint(address(user), amount);
        vm.prank(user);
        token.approve(address(orderManager), amount);
        vm.stopPrank();
    }

    function testUnauthorizedExecutor_reverts() public {
        // Arrange
        StopMarketOrder memory order = StopMarketOrder({
            user: address(1),
            orderId: 1,
            amountIn: 1 ether,
            tokenIn: address(2),
            tokenOut: address(3),
            ttl: block.timestamp + 1 hours,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });
        bytes memory mockSwapData = abi.encodePacked(uint256(1));

        // Create a valid signature for the order
        bytes32 digest = createDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Act & Assert: Unauthorized executor should revert
        vm.prank(address(0x123)); // Simulate an unauthorized executor
        vm.expectRevert(UnauthorizedExecutor.selector);
        orderManager.executeOrder(order, mockSwapData, mockSwapData, v, r, s, 0);
    }

    function testExecuteOrder_success() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 fee = 0.2 ether;

        prepareTokenForUser(user, tokenIn, amountIn);
        tokenOut.mint(address(mockRouter), 1_000 ether);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), amountIn - fee, amountOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenIn), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(address(this), user, orderId, amountOutMin, address(tokenOut), fee);

        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);

        (uint256 amountOut,) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, 0.8 ether, "amountsOut mismatch");
    }

    function testFuzzExecuteOrder_success(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 userSwapAmountIn,
        uint256 feeAmountIn
    ) public {
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether); // Ensure reasonable input
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn); // Ensure amountOutMin is valid
        vm.assume(userSwapAmountIn > 0 && userSwapAmountIn <= amountIn); // Ensure swap amount is within bounds
        vm.assume(feeAmountIn > 0 && feeAmountIn <= (amountIn - userSwapAmountIn)); // Fee must not exceed remaining balance

        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 ttl = block.timestamp + 1 hours;

        MockERC20 tokenIn = new MockERC20("TokenIn", "TIN");
        MockERC20 tokenOut = new MockERC20("TokenOut", "TOUT");
        prepareTokenForUser(user, tokenIn, amountIn);
        tokenOut.mint(address(mockRouter), 1_000 ether);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), userSwapAmountIn, amountOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenIn), address(weth), feeAmountIn, feeAmountIn);

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(
            address(this), user, orderId, amountOutMin, address(tokenOut), feeAmountIn
        );

        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);

        (uint256 amountOut, address tOut) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, amountOutMin, "amountsOut mismatch");
        assertEq(tOut, address(tokenOut), "tokenOut mismatch");
    }

    function testExecuteOrder_tokenInWeth_success() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 fee = 0.2 ether;

        MockERC20 tokenIn = weth;
        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), amountIn - fee, amountOutMin);

        uint256 executorBalanceBefore = address(this).balance;
        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(address(this), user, orderId, amountOutMin, address(tokenOut), fee);

        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);

        (uint256 amountOut,) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, 0.8 ether, "amountsOut mismatch");
        assertEq(address(this).balance - executorBalanceBefore, fee, "fee mismatch");
    }

    function testFuzzExecuteSwapForUser_tokenInWeth_success(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 userSwapAmountIn,
        uint256 feeAmountIn
    ) public {
        // Input Assumptions
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether); // Ensure reasonable `amountIn`
        vm.assume(amountOutMin > 0 && amountOutMin < amountIn); // Ensure valid `amountOutMin`
        vm.assume(userSwapAmountIn > 0 && userSwapAmountIn <= amountOutMin); // Ensure `userSwapAmountIn` is within bounds
        vm.assume(feeAmountIn > 0 && feeAmountIn <= (amountIn - userSwapAmountIn)); // Ensure valid `feeAmountIn`

        uint256 orderId = 1;
        uint256 ttl = block.timestamp + 1 hours;

        MockERC20 tokenIn = weth; // Token is WETH
        prepareTokenForUser(user, tokenIn, amountIn); // Prepare user's token balance

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), userSwapAmountIn, amountOutMin);

        uint256 executorBalanceBefore = address(this).balance;
        bytes memory swapData = abi.encodePacked(uint256(1));

        uint256 expectedFee = amountIn - userSwapAmountIn;
        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(
            address(this), user, orderId, amountOutMin, address(tokenOut), expectedFee
        );

        // Execute the order
        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);

        // Assertions
        (uint256 amountOut,) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, amountOutMin, "amountsOut mismatch");
        assertEq(address(this).balance - executorBalanceBefore, expectedFee, "fee mismatch");
    }

    function testExecuteSwapForUser_emptyFeeSwapData_success() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 userSwapAmountIn = 0.8 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;

        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), userSwapAmountIn, amountOutMin);

        bytes memory emptyFeeSwapData = "";

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(address(this), user, orderId, amountOutMin, address(tokenOut), 0);

        uint256 executorBalanceBefore = address(this).balance;
        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeOrder(order, swapData, emptyFeeSwapData, v, r, s, 0);

        (uint256 amountOut,) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, amountOutMin, "amountsOut mismatch");
        assertEq(address(this).balance - executorBalanceBefore, 0, "fee mismatch");
    }

    function testFuzzExecuteSwapForUser_emptyFeeSwapData_success(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 userSwapAmountIn,
        uint256 feeAmountIn
    ) public {
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether); // Ensure reasonable input
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn); // Ensure amountOutMin is valid
        vm.assume(userSwapAmountIn > 0 && userSwapAmountIn <= amountIn); // Ensure swap amount is within bounds
        vm.assume(feeAmountIn > 0 && feeAmountIn <= (amountIn - userSwapAmountIn)); // Fee must not exceed remaining balance

        uint256 orderId = 1;
        uint256 ttl = block.timestamp + 1 hours;

        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), userSwapAmountIn, amountOutMin);

        bytes memory emptyFeeSwapData = "";

        vm.expectEmit(true, true, true, true);
        emit OrderManagerV1.OpenOrderExecuted(address(this), user, orderId, amountOutMin, address(tokenOut), 0);

        uint256 executorBalanceBefore = address(this).balance;
        bytes memory swapData = abi.encodePacked(uint256(1));
        orderManager.executeOrder(order, swapData, emptyFeeSwapData, v, r, s, 0);

        (uint256 amountOut,) = orderManager.getAmountOut(orderId);
        assertEq(tokenOut.balanceOf(user), amountOutMin, "amountOut mismatch");
        assertEq(amountOut, amountOutMin, "amountsOut mismatch");
        assertEq(address(this).balance - executorBalanceBefore, 0, "fee mismatch");
    }

    function testExecuteSwapForUser_amountOutMismatch_reverted() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 1 ether; // Expected amount out
        uint256 mismatchedAmountOut = 0.5 ether; // Actual amount out (lower than expected)

        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenIn),
            address(tokenOut),
            amountIn,
            mismatchedAmountOut // This simulates the mismatch
        );

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(AmountOutTooLow.selector, user, orderId, mismatchedAmountOut, amountOutMin)
        );

        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);
    }

    function testFuzzExecuteSwapForUser_amountOutMismatch_reverted(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 mismatchedAmountOut
    ) public {
        // Ensure valid fuzzed input ranges
        vm.assume(amountIn > 0 && amountIn <= 1_000 ether);
        vm.assume(amountOutMin > 0 && amountOutMin <= amountIn);
        vm.assume(mismatchedAmountOut > 0 && mismatchedAmountOut < amountOutMin); // Ensure mismatch occurs

        uint256 orderId = 1;
        uint256 ttl = block.timestamp + 1 hours;

        prepareTokenForUser(user, tokenIn, amountIn);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        mockRouter.expectSwap(
            user,
            address(tokenIn),
            address(tokenOut),
            amountIn,
            mismatchedAmountOut // This simulates the mismatch
        );

        bytes memory swapData = abi.encodePacked(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(AmountOutTooLow.selector, user, orderId, mismatchedAmountOut, amountOutMin)
        );

        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);
    }

    function testExecuteSwapForUser_feeGreaterThanBalance_revert() public {
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 0.8 ether;
        uint256 fee = 0.3 ether; // fee + amountOutMin > amountIn, so the fee swap should fail

        prepareTokenForUser(user, tokenIn, amountIn + fee);

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            ttl: ttl,
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = createDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        mockRouter.expectSwap(user, address(tokenIn), address(tokenOut), amountOutMin, amountOutMin);
        mockRouter.expectSwap(address(orderManager), address(tokenIn), address(weth), fee, fee);

        bytes memory swapData = abi.encodePacked(uint256(1));

        // transferFrom will fail in MockRouter due to insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapFailed.selector,
                user,
                orderId,
                hex"fb8f41b20000000000000000000000005991a2df15a8f6a256d3ec51e99254cd3fb576a900000000000000000000000000000000000000000000000002c68af0bb1400000000000000000000000000000000000000000000000000000429d069189e0000"
            )
        );
        orderManager.executeOrder(order, swapData, swapData, v, r, s, 0);
    }

    receive() external payable {}
}
