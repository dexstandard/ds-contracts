// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/OrderManagerV1.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script, console} from "forge-std/Script.sol";

contract OrderManagerV1Script is Script {
    OrderManagerV1 public implementation;
    TransparentUpgradeableProxy public proxy;

    function run() public {
        address admin = address(msg.sender);
        address executorAddress = address(msg.sender);

        // https://docs.uniswap.org/contracts/v3/reference/deployments/arbitrum-deployments
        // SwapRouter02 address on Arbitrum
        address uniswapRouterAddress = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        // https://arbiscan.io/token/0x82af49447d8a07e3bd95bd0d56f35241523fbab1
        address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        vm.startBroadcast();

        // Deploy the implementation contract
        implementation = new OrderManagerV1();

        // Encode the initialization data
        bytes memory initializeData = abi.encodeWithSelector(
            OrderManagerV1.initialize.selector,
            executorAddress,
            uniswapRouterAddress,
            wethAddress
        );

        console.log("Encoded initialization data:");
        console.logBytes(initializeData);

        // Deploy the Transparent Proxy
        proxy = new TransparentUpgradeableProxy(
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

        // Print the encoded constructor arguments for contract verification
        console.log("Encoded proxy constructor arguments:");
        console.logBytes(constructorArgs);

        vm.stopBroadcast();
    }
}
