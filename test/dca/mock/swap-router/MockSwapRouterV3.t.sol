// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IV3SwapRouter} from "@uniswap/smart-router-contracts/interfaces/IV3SwapRouter.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Script.sol";

contract MockSwapRouterV3 {
    struct SwapConfig {
        address expectedRecipient;
        address tokenIn;
        address tokenOut;
        uint256 expectedAmountIn;
        uint256 amountOut;
    }

    SwapConfig[] public swapConfigs;
    uint256 public active;

    function expectExactInput(address recipient, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        external
    {
        swapConfigs.push(
            SwapConfig({
                expectedRecipient: recipient,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                expectedAmountIn: amountIn,
                amountOut: amountOut
            })
        );
    }

    error UnexpectedCall(uint256 index);
    error ParamMismatch(string which, bytes32 got, bytes32 expected);
    error TokenTransferFailed(address token, address to, uint256 amt);

    function exactInput(IV3SwapRouter.ExactInputParams calldata p)
        external
        payable
        returns (uint256 amountOutReturned)
    {
        if (active >= swapConfigs.length) revert UnexpectedCall(active);
        SwapConfig storage cfg = swapConfigs[active];

        /* ───────────── validate params ───────────── */
        _eq("recipient", bytes32(uint256(uint160(p.recipient))), bytes32(uint256(uint160(cfg.expectedRecipient))));
        _eq("amountIn", bytes32(p.amountIn), bytes32(cfg.expectedAmountIn));

        (address tokenIn, address tokenOut) = _decodeTokens(p.path);
        _eq("tokenIn", bytes32(uint256(uint160(tokenIn))), bytes32(uint256(uint160(cfg.tokenIn))));
        _eq("tokenOut", bytes32(uint256(uint160(tokenOut))), bytes32(uint256(uint160(cfg.tokenOut))));

        /* ───────────── pull tokenIn ───────────── */
        if (!IERC20(tokenIn).transferFrom(msg.sender, address(this), p.amountIn)) {
            revert TokenTransferFailed(tokenIn, address(this), p.amountIn);
        }

        /* ───────────── push tokenOut ──────────── */
        if (!IERC20(tokenOut).transfer(p.recipient, cfg.amountOut)) {
            revert TokenTransferFailed(tokenOut, p.recipient, cfg.amountOut);
        }

        ++active;
        return cfg.amountOut;
    }

    /* ───────────────────── helper utils ───────────────────── */

    function _decodeTokens(bytes calldata path) private pure returns (address tokenIn, address tokenOut) {
        require(path.length >= 43, "path too short"); // 20 + 3 + 20
        tokenIn = address(bytes20(path[0:20]));
        tokenOut = address(bytes20(path[path.length - 20:]));
    }

    function _eq(string memory tag, bytes32 a, bytes32 b) private pure {
        if (a != b) revert ParamMismatch(tag, a, b);
    }

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams calldata) external payable returns (uint256) {
        revert("exactInputSingle not mocked");
    }

    function exactOutput(IV3SwapRouter.ExactOutputParams calldata) external payable returns (uint256) {
        revert("exactOutput not mocked");
    }

    function exactOutputSingle(IV3SwapRouter.ExactOutputSingleParams calldata) external payable returns (uint256) {
        revert("exactOutputSingle not mocked");
    }
}
