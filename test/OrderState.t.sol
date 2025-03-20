// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/OrderManagerV1.sol";
import "./OrderManagerV1Testable.sol";
import {Test} from "forge-std/Test.sol";

contract NonceUseTest is Test {
    OrderManagerV1Testable orderManager;

    function setUp() public {
        OrderManagerV1Testable implementation = new OrderManagerV1Testable();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        orderManager = OrderManagerV1Testable(payable(address(proxy)));
        orderManager.initialize(address(this), address(0x111), address(0x112));
    }

    function testNonceUseOnce_success() public {
        // Arrange
        address user = vm.addr(1);
        uint256 nonce = 0;

        // Act: Use the nonce for the first time
        orderManager.markPositionsOpened(user, nonce);

        // Assert: No revert means success
    }

    function testNonceReuse_fails() public {
        // Arrange
        address user = vm.addr(1);
        uint256 nonce = 0;

        // Use the nonce the first time
        orderManager.markPositionsOpened(user, nonce);

        // Act & Assert: Reuse the same nonce and expect it to revert
        vm.expectRevert(SignatureAlreadyUsed.selector);
        orderManager.markPositionsOpened(user, nonce);
    }

    function testFuzzNonceUseOnce_success(address user, uint256 nonce) public {
        // Ensure the user address is valid (non-zero)
        user = vm.addr(uint160(uint256(keccak256(abi.encode(user))) % type(uint160).max));
        nonce = bound(nonce, 0, type(uint256).max);

        // Act: Use the nonce for the first time
        orderManager.markPositionsOpened(user, nonce);

        // Assert: No revert means success
    }

    function testFuzzNonceReuse_fails(address user, uint256 nonce) public {
        // Ensure the user address is valid (non-zero)
        user = vm.addr(uint160(uint256(keccak256(abi.encode(user))) % type(uint160).max));
        nonce = bound(nonce, 0, type(uint256).max);

        // Use the nonce the first time
        orderManager.markPositionsOpened(user, nonce);

        // Act & Assert: Reuse the same nonce and expect it to revert
        vm.expectRevert(SignatureAlreadyUsed.selector);
        orderManager.markPositionsOpened(user, nonce);
    }

    function testNonceUseOnce_takeProfit_success() public {
        // Arrange
        address user = vm.addr(1);
        uint256 nonce = 0;

        // Act: Use the nonce for the first time
        orderManager.markPositionClosed(user, nonce);

        // Assert: No revert means success
    }

    function testNonceReuse_takeProfit_fails() public {
        // Arrange
        address user = vm.addr(1);
        uint256 nonce = 0;

        // Use the nonce the first time
        orderManager.markPositionClosed(user, nonce);

        // Act & Assert: Reuse the same nonce and expect it to revert
        vm.expectRevert(SignatureAlreadyUsed.selector);
        orderManager.markPositionClosed(user, nonce);
    }
}
