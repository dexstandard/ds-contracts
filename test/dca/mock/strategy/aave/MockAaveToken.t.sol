// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract MockAaveToken is ERC20Upgradeable {
    address public underlyingAsset;
    address public pool;
    address public incentivesController;

    // Use an initializer in place of a constructor for upgradeable contracts
    function initialize(
        string memory name_,
        string memory symbol_,
        address _underlyingAsset,
        address _incentivesController
    ) external initializer {
        __ERC20_init(name_, symbol_);
        underlyingAsset = _underlyingAsset;
        incentivesController = _incentivesController;
    }

    function setPool(address _pool) external {
        pool = _pool;
    }

    // AToken-specific functions:
    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return underlyingAsset;
    }

    function POOL() external view returns (address) {
        return pool;
    }

    function getIncentivesController() external view returns (address) {
        return incentivesController;
    }

    function mint(address user, address onBehalfOf, uint256 amount, uint256 liquidityIndex) external returns (bool) {
        _mint(onBehalfOf, amount);
        return true;
    }

    function burn(address user, uint256 amount) external returns (bool) {
        _burn(user, amount);
        return true;
    }
}
