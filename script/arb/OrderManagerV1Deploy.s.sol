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
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uni Arbitrum
            0x1F721E2E82F6676FCE4eA07A5958cF098D339e18, // Camelot
            0x32226588378236Fd0c7c4053999F88aC0e5cAc77, // Pancake
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 // WETH Arbitrum
        );
    }
}
