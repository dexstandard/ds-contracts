// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/OrderManagerV1.sol";

contract OrderManagerV1UpgradeBase is Script {
    /// @notice Deploy a new implementation and schedule the upgrade on the provided proxy.
    /// @param proxyAddress The proxy address.
    /// @return newImplAddress The address of the newly deployed implementation.
    function scheduleUpgrade(
        address proxyAddress
    ) internal returns (address newImplAddress) {
        vm.startBroadcast();

        OrderManagerV1 newImpl = new OrderManagerV1();
        newImplAddress = address(newImpl);
        console.log("New implementation deployed at:", newImplAddress);

        OrderManagerV1 orderManager = OrderManagerV1(payable(proxyAddress));
        orderManager.scheduleUpgrade(newImplAddress);
        console.log(
            "Upgrade scheduled with new implementation:",
            newImplAddress
        );

        vm.stopBroadcast();
    }

    /// @notice Execute the upgrade by calling upgradeTo on the provided proxy.
    /// @param proxyAddress The proxy address.
    /// @param newImplAddress The new implementation address that was scheduled earlier.
    function upgrade(address proxyAddress, address newImplAddress) internal {
        vm.startBroadcast();

        ITransparentUpgradeableProxy(proxyAddress).upgradeToAndCall(
            newImplAddress,
            ""
        );
        console.log(
            "Upgrade executed. Proxy now points to new implementation:",
            newImplAddress
        );

        vm.stopBroadcast();
    }
}
