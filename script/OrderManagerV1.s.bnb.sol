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

        // https://docs.uniswap.org/contracts/v3/reference/deployments/bnb-deployments
        // SwapRouter02 address on BNB
        address uniswapRouterAddress = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;
        // https://bscscan.com/token/0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c
        address wethAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

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
