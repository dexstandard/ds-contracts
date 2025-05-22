// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAaveV3Incentives} from "../../../../../src/yield/interfaces/aave/IAaveV3Incentives.sol";

contract MockAaveIncentives is IAaveV3Incentives {
    uint256 public lastClaimed;

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        override
        returns (uint256)
    {
        lastClaimed = amount;
        return amount;
    }

    function getUserRewards(address[] calldata assets, address user, address reward)
        external
        view
        override
        returns (uint256)
    {
        return 0;
    }

    function claimAllRewards(address[] calldata assets, address to) external override returns (uint256) {
        return 0;
    }
}
