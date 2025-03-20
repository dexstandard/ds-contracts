// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../src/OrderManagerV1.sol";
import "./mock/MockUniswapRouter.sol";

contract OrderManagerV1Testable is OrderManagerV1 {
    function verifySignature(StopMarketOrder calldata order, uint8 v, bytes32 r, bytes32 s) external view {
        _verifySignature(order, v, r, s);
    }

    function markPositionsOpened(address user, uint256 orderId) external {
        _markPositionOpened(user, orderId);
    }

    function markPositionClosed(address user, uint256 orderId) external {
        _markPositionClosed(user, orderId);
    }

    function validateOrder(uint256 ttl, uint256 amountOutMin) external view {
        _validateOrder(ttl, amountOutMin);
    }
}
