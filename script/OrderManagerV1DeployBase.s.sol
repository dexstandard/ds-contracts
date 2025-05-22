// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/OrderManagerV1.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script, console} from "forge-std/Script.sol";

abstract contract OrderManagerV1DeployBase is Script {
    function getDeploymentConfig()
        internal
        virtual
    returns (address uniswapRouter, address sushiRouter, address pancakeRouter, address weth);

    function run() public {
        address admin = msg.sender;
        address executorAddress = msg.sender;

        (
            address uniswapRouterAddress,
            address sushiRouterAddress,
            address pancakeRouterAddress,
            address wethAddress
        ) = getDeploymentConfig();

        vm.startBroadcast();

        // Deploy implementation
        OrderManagerV1 implementation = new OrderManagerV1();

        // Encode initializer
        bytes memory initializeData = abi.encodeWithSelector(
            OrderManagerV1.initialize.selector,
            executorAddress,
            uniswapRouterAddress,
            sushiRouterAddress,
            pancakeRouterAddress,
            wethAddress
        );

        console.log("Encoded initialization data:");
        console.logBytes(initializeData);

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            initializeData
        );

        console.log("Implementation deployed at:", address(implementation));
        console.log("Proxy deployed at:", address(proxy));

        bytes memory constructorArgs = abi.encode(
            address(implementation),
            admin,
            initializeData
        );

        console.log("Encoded proxy constructor arguments:");
        console.logBytes(constructorArgs);

        vm.stopBroadcast();
    }
}