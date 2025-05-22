// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPool} from "@aaveV3/interfaces/IPool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {AToken} from "@aaveV3/protocol/tokenization/AToken.sol";
import {MockAaveToken} from "./MockAaveToken.t.sol";

contract MockAavePool {
    mapping(address => uint256) public supplied;

    // We add an aToken variable so that we can simulate minting.
    address public aToken;

    event Supply(address indexed asset, address indexed from, uint256 amount);
    event Withdraw(address indexed asset, address indexed to, uint256 amount);

    constructor(address _aToken) {
        aToken = _aToken;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /* referralCode */ ) external {
        require(amount > 0, "MockAavePool: amount must be > 0");

        // Transfer tokens from msg.sender to the pool.
        // This subtracts tokens from the caller (usually the strategy).
        bool success = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(success, "MockAavePool: transferFrom failed");

        // Update the supplied amount.
        supplied[asset] += amount;

        require(aToken != address(0), "MockAavePool: aToken not set");
        MockAaveToken(aToken).mint(msg.sender, onBehalfOf, amount, 1e18);

        // Emit an event for testing purposes.
        emit Supply(asset, onBehalfOf, amount);
    }

    /**
     * @dev Simulates withdrawing an asset from the pool.
     * - Checks the available supplied balance.
     * - If the requested amount exceeds what is available, adjusts it to the available balance.
     * - Decreases the supplied amount accordingly.
     * - Transfers the tokens from the pool to the `to` address.
     * - Emits a Withdraw event and returns the actual withdrawn amount.
     *
     * @param asset The ERC20 token address.
     * @param amount The requested amount to withdraw.
     * @param to The recipient of the tokens.
     * @return The actual withdrawn amount.
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        uint256 available = supplied[asset];
        if (amount > available) {
            amount = available;
        }
        supplied[asset] -= amount;

        // Transfer tokens from the pool to the recipient.
        bool success = IERC20(asset).transfer(to, amount);
        require(success, "MockAavePool: transfer failed");
        MockAaveToken(aToken).burn(msg.sender, amount);

        // Emit an event for testing.
        emit Withdraw(asset, to, amount);
        return amount;
    }
}
