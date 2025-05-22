// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DCAOrderManagerV1} from "../src/dca/DCAOrderManagerV1.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script, console} from "forge-std/Script.sol";

abstract contract DCAOrderManagerV1DeployBase is Script {
    function getDeploymentConfig()
        internal
        virtual
        returns (address uniswapRouter, address pancakeRouter, address wethAddress);

    function run() public {
        address owner = msg.sender;
        address executor = 0x36A45A152B27720d4E2bb0F529631E94730e277B;

        (address uniswapRouter, address pancakeRouter, address wethAddress) = getDeploymentConfig();

        vm.startBroadcast();

        // Deploy implementation
        DCAOrderManagerV1 implementation = new DCAOrderManagerV1();

        // Encode initializer
        bytes memory initializeData = abi.encodeWithSelector(
            DCAOrderManagerV1.initialize.selector, executor, uniswapRouter, pancakeRouter, wethAddress
        );

        console.log("DCA Order Manager encoded initialization data:");
        console.logBytes(initializeData);

        // Deploy proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), owner, initializeData);

        console.log("DCA Order Manager implementation deployed at:", address(implementation));
        console.log("DCA Order Manager proxy deployed at:", address(proxy));

        bytes memory constructorArgs = abi.encode(address(implementation), owner, initializeData);

        console.log("DCA Order Manager encoded proxy constructor arguments:");
        console.logBytes(constructorArgs);

        vm.stopBroadcast();
    }
}
