// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {console} from "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Import the old and new versions.
import {OrderManagerV0} from "../src/OrderManagerV0.sol";
import {OrderManagerV1} from "../src/OrderManagerV1.sol";

// Mocks for router and ERC20
import "./mock/MockUniswapRouterV2.sol";
import "./mock/MockERC20.sol";

contract OrderManagerUpgradeTest is Test {
    OrderManagerV0 public oldManager;
    OrderManagerV1 public upgradedManager;
    TransparentUpgradeableProxy public proxy;

    MockUniswapRouterV2 public mockUniswapRouter;
    MockERC20 public weth;
    address public owner;
    address public executor;

    function setUp() public {
        owner = vm.addr(1);
        executor = vm.addr(2);

        mockUniswapRouter = new MockUniswapRouterV2();
        weth = new MockERC20("Wrapped ETH", "WETH");

        // --- DEPLOY OLD IMPLEMENTATION (V0) ---
        vm.startBroadcast(owner);
        OrderManagerV0 oldImpl = new OrderManagerV0();
        bytes memory initData = abi.encodeWithSelector(
            OrderManagerV0.initialize.selector,
            executor,
            address(mockUniswapRouter),
            address(weth)
        );
        proxy = new TransparentUpgradeableProxy(
            address(oldImpl),
            owner, // proxy admin
            initData
        );
        vm.stopBroadcast();

        oldManager = OrderManagerV0(payable(address(proxy)));

        assertEq(oldManager.owner(), owner, "V0: owner mismatch");
        assertEq(oldManager.executor(), executor, "V0: executor mismatch");
        assertEq(
            oldManager.uniswapRouter(),
            address(mockUniswapRouter),
            "V0: uniswapRouter mismatch"
        );
        assertEq(
            oldManager.WETH_ADDRESS(),
            address(weth),
            "V0: WETH address mismatch"
        );
    }

    function testUpgradeFlow() public {
        // --- UPGRADE TO NEW IMPLEMENTATION (V1) ---
        vm.startBroadcast(owner);
        OrderManagerV1 newImpl = new OrderManagerV1();
        address newImplAddress = address(newImpl);

        oldManager.scheduleUpgrade(newImplAddress);
        vm.stopBroadcast();

        vm.warp(block.timestamp + 2 days);

        vm.startBroadcast(owner);
        ITransparentUpgradeableProxy(address(proxy)).upgradeToAndCall(
            newImplAddress,
            ""
        );
        vm.stopBroadcast();

        upgradedManager = OrderManagerV1(payable(address(proxy)));

        // --- CHECK STORAGE (MIXED UP) ---
        // In V0, the storage order for addresses was:
        //   slot3: WETH_ADDRESS, slot4: owner, slot5: uniswapRouter, slot6: executor.
        // In V1, the expected order is:
        //   slot3: WETH_ADDRESS, slot4: owner, slot5: router0, slot6: router1, slot7: router2, slot8: executor.
        //   upgradedManager.WETH_ADDRESS() == weth
        //   upgradedManager.owner()       == owner
        //   upgradedManager.router0()     == uniswapRouter
        //   upgradedManager.router1()     == executor
        //   upgradedManager.router2()     == 0
        //   upgradedManager.executor()    == 0

        assertEq(
            upgradedManager.WETH_ADDRESS(),
            address(weth),
            "V1: WETH address mismatch after upgrade"
        );
        assertEq(
            upgradedManager.owner(),
            owner,
            "V1: owner mismatch after upgrade"
        );
        assertEq(
            upgradedManager.router0(),
            address(mockUniswapRouter),
            "V1: router0 (should equal old uniswapRouter)"
        );
        assertEq(
            upgradedManager.router1(),
            executor,
            "V1: router1 (should equal old executor)"
        );
        assertEq(
            upgradedManager.router2(),
            address(0),
            "V1: router2 should be zero"
        );
        assertEq(
            upgradedManager.executor(),
            address(0),
            "V1: executor should be zero"
        );
    }
}
