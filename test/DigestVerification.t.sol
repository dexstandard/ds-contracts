// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/OrderManagerV1.sol";
import "./OrderManagerV1Testable.sol";
import {Test} from "forge-std/Test.sol";

contract DigestVerificationTest is Test {
    OrderManagerV1Testable orderManager;

    function setUp() public {
        OrderManagerV1Testable implementation = new OrderManagerV1Testable();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        orderManager = OrderManagerV1Testable(payable(address(proxy)));
        orderManager.initialize(
            address(this),
            address(0x111),
            address(0x111),
            address(0x111),
            address(0x112)
        );
    }

    function testVerifySignature_success() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = keccak256(
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Act
        vm.prank(user);
        orderManager.verifySignature(order, v, r, s);

        // Assert
        // No revert means success
    }

    function testFuzzVerifySignature_success(
        uint256 signerKey,
        uint256 orderId,
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 ttlOffset
    ) public {
        // Ensure signerKey is within the valid range for Secp256k1
        signerKey = bound(signerKey, 1, type(uint256).max - 1);
        signerKey = bound(signerKey, 1, 115792089237316195423570985008687907852837564279074904382605163141518161494336);

        address signerAddress = vm.addr(signerKey);

        // Ensure TTL is valid and in the future
        ttlOffset = bound(ttlOffset, 1, 365 days);
        uint256 ttl = block.timestamp + ttlOffset;

        // Ensure valid orderId and amountIn
        orderId = bound(orderId, 1, type(uint256).max);
        amountIn = bound(amountIn, 1 ether, type(uint256).max);

        // Arrange
        StopMarketOrder memory order = StopMarketOrder({
            user: signerAddress,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Compute digest
        bytes32 digest = keccak256(
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

        // Sign digest with the private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        // Act
        vm.prank(signerAddress);
        orderManager.verifySignature(order, v, r, s);

        // Assert
        // No revert means success
    }

    function testVerifySignature_orderVerificationFailed() public {
        // Arrange
        address user = vm.addr(1);
        address attacker = vm.addr(2);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(3);
        address tokenOut = vm.addr(4);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = keccak256(
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
                        order.takeProfitOutMin
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest); // Signed by attacker

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(order, v, r, s);
    }

    function testVerifySignature_malformedDigest() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Create a malformed digest (wrong encoding)
        bytes32 malformedDigest = keccak256(
            abi.encode(
                order.user, // Missing EIP-191 prefix and DOMAIN_SEPARATOR
                order.orderId,
                order.amountIn,
                order.tokenIn,
                order.tokenOut,
                order.ttl,
                order.amountOutMin,
                order.takeProfitOutMin
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, malformedDigest);

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(order, v, r, s);
    }

    function testVerifySignature_wrongContractReference() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Create a digest with a different contract reference
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256("OrderManagerV1"),
                        keccak256("1"),
                        block.chainid,
                        vm.addr(99) // Wrong contract reference
                    )
                ),
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
                        order.takeProfitOutMin
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(order, v, r, s);
    }

    function testVerifySignature_wrongTypeReference() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Create a digest with a different ORDER_TYPEHASH
        bytes32 wrongTypeHash = keccak256(
            abi.encode(
                keccak256(
                    "WrongOrder(address user,uint256 orderId,uint256 amountIn,address tokenIn,address tokenOut,uint256 ttl)"
                ),
                order.user,
                order.orderId,
                order.amountIn,
                order.tokenIn,
                order.tokenOut,
                order.ttl,
                order.amountOutMin,
                order.takeProfitOutMin
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", orderManager.DOMAIN_SEPARATOR(), wrongTypeHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(order, v, r, s);
    }

    function testVerifySignature_malformedBodyObject() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;

        StopMarketOrder memory order = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        bytes32 digest = keccak256(
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
                        order.takeProfitOutMin
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Alter the body object (e.g., modify amountIn)
        StopMarketOrder memory malformedOrder = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn + 1, // Change amountIn to create a malformed order
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl,
            amountOutMin: 30,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(malformedOrder, v, r, s);
    }

    function testVerifySignature_missingField() public {
        // Arrange
        address user = vm.addr(1);
        uint256 orderId = 1;
        uint256 amountIn = 1 ether;
        address tokenIn = vm.addr(2);
        address tokenOut = vm.addr(3);
        uint256 ttl = block.timestamp + 1 hours;
        uint256 amountOutMin = 30;
        uint256 takeProfitOutMin = 0;

        // Use the reduced PartialOrder structure for signing
        bytes32 partialOrderHash = keccak256(
            abi.encode(
                keccak256(
                    "PartialOrder(address user,uint256 orderId,uint256 amountIn,address tokenIn,address tokenOut)"
                ),
                user,
                orderId,
                amountIn,
                tokenIn,
                tokenOut,
                amountOutMin,
                takeProfitOutMin
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", orderManager.DOMAIN_SEPARATOR(), partialOrderHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        // Attempt to execute the order with the full Order struct
        StopMarketOrder memory malformedOrder = StopMarketOrder({
            user: user,
            orderId: orderId,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            ttl: ttl, // This field was missing during signing
            amountOutMin: amountOutMin,
            takeProfitOutMin: 0,
            stopLossOutMin: 0
        });

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(OrderVerificationFailed.selector);
        orderManager.verifySignature(malformedOrder, v, r, s);
    }
}
