// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../OrderManagerV1DeployBase.s.sol";

contract OrderManagerV1Deploy is OrderManagerV1DeployBase {
    function getDeploymentConfig()
        internal
        pure
        override
        returns (
            address uniswapRouter,
            address sushiRouter,
            address pancakeRouter,
            address weth
        )
    {
        return (
            0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2, // uniswap bsc
            0x0000000000000000000000000000000000000000, // camelot
            0x13f4EA83D0bd40E75C8222255bc855a974568Dd4, // pancake
            0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c // WBNB
        );
    }
}
