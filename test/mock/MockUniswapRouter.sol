// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockUniswapRouter {
    event SwapExecuted(address sender, bytes data);

    fallback() external payable {
        // If empty data => simulate (success=false, "")
        if (msg.data.length == 0) {
            // We want the main contract to see (success=false, ""),
            // so revert here with no data. Then at the main contract side,
            // `(!success)` becomes true.
            assembly {
                revert(0, 0)
            }
        }

        // Otherwise, log that a swap was “executed”
        emit SwapExecuted(msg.sender, msg.data);

        // Return something like (true, 12345). In raw EVM fallback,
        // you do inline assembly to return the bytes. For simplicity:
        assembly {
            mstore(0, 12345)
            return(0, 32)
        }
    }
}
