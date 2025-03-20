// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/OrderManagerV1.sol";
import "./mock/MockUniswapRouterV2.sol";
import "forge-std/console.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

contract ContractUpgradeTest is Test {
    OrderManagerV1 orderManager;
    MockUniswapRouterV2 mockRouter;
    MockERC20 weth = new MockERC20("wrappedETH", "WETH");

    TransparentUpgradeableProxy proxy;

    function setUp() public {
        // Deploy mock router
        mockRouter = new MockUniswapRouterV2();

        // Deploy implementation contract
        OrderManagerV1 implementation = new OrderManagerV1();

        // Deploy TransparentUpgradeableProxy
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this), // Admin
            ""
        );

        // Initialize orderManager via the proxy
        orderManager = OrderManagerV1(payable(address(proxy)));
        orderManager.initialize(address(this), address(mockRouter), address(weth));
    }

    function testUpgrade_success() public {
        // Deploy a new implementation
        OrderManagerV1 newImplementation = new OrderManagerV1();

        // Schedule the upgrade
        orderManager.scheduleUpgrade(address(newImplementation));

        // Advance time to simulate the delay (2 days)
        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(address(newImplementation));
        // Upgrade the implementation
        ITransparentUpgradeableProxy(address(proxy)).upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgrade_tooEarly_fails() public {
        // Deploy a new implementation
        OrderManagerV1 newImplementation = new OrderManagerV1();

        // Schedule the upgrade
        orderManager.scheduleUpgrade(address(newImplementation));

        // Attempt to upgrade before the delay period has elapsed
        vm.expectRevert("Upgrade still locked");
        ITransparentUpgradeableProxy(address(proxy)).upgradeToAndCall(address(newImplementation), "");
    }
}
