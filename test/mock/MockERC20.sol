// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Mock WETH-like withdraw method to convert tokens to ETH
    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Burn the tokens from the caller's balance
        _burn(msg.sender, amount);

        // Send the equivalent ETH to the caller
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // Allow the contract to accept ETH (for test scenarios if needed)
    receive() external payable {}
}
