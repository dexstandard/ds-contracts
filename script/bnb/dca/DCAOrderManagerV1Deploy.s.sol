// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../DCAOrderManagerV1DeployBase.s.sol";

contract DCAOrderManagerV1Deploy is DCAOrderManagerV1DeployBase {
    function getDeploymentConfig()
        internal
        pure
        override
        returns (address uniswapRouter, address pancakeRouter, address weth)
    {
        return (
            0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2, // Uni BNB
            0x13f4EA83D0bd40E75C8222255bc855a974568Dd4, // Pancake BNB
            0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c // WBNB
        );
    }
}
