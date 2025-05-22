// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockOnchainSwapper {
    using SafeERC20 for IERC20;

    function swap(address tokenFrom, address tokenTo, uint256 amount) external returns (uint256) {
        require(amount != 0, "MockSwapper: amount = 0");

        IERC20(tokenFrom).safeTransferFrom(msg.sender, address(this), amount);
        MockERC20(payable(tokenTo)).mint(address(this), amount);

        IERC20(tokenTo).safeTransfer(msg.sender, amount);

        return amount;
    }
}
