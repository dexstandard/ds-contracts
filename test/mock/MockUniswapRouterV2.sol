// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MockUniswapRouterV2 {
    struct SwapConfig {
        address recipient;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
    }

    // Store multiple configurations
    SwapConfig[] public swapConfigs;
    uint256 public activeConfigIndex = 0;

    // Prepare swap parameters
    function expectSwap(address _recipient, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOut)
        external
    {
        swapConfigs.push(
            SwapConfig({
                recipient: _recipient,
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                amountIn: _amountIn,
                amountOut: _amountOut
            })
        );
    }

    error EmptyDataNotAllowed();
    error SwapNotPrepared(uint256 activeConfigIndex);
    error TokenInTransferFailed(address tokenIn, address sender, uint256 amount);
    error TokenOutTransferFailed(address tokenOut, address recipient, uint256 amount);
    error UnexpectedCall();

    // Fallback function to handle swaps
    fallback() external payable {
        if (activeConfigIndex >= swapConfigs.length) revert UnexpectedCall();
        if (msg.data.length == 0) revert EmptyDataNotAllowed();

        SwapConfig storage config = swapConfigs[activeConfigIndex];

        if (config.amountIn == 0 || config.amountOut == 0) {
            revert SwapNotPrepared(activeConfigIndex);
        }

        if (!IERC20(config.tokenIn).transferFrom(msg.sender, address(this), config.amountIn)) {
            revert TokenInTransferFailed(config.tokenIn, msg.sender, config.amountIn);
        }

        if (!IERC20(config.tokenOut).transfer(config.recipient, config.amountOut)) {
            revert TokenOutTransferFailed(config.tokenOut, config.recipient, config.amountOut);
        }

        activeConfigIndex++;
    }

    receive() external payable {}
}
