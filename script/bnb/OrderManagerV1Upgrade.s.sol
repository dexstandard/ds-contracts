// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../OrderManagerV1UpgradeBase.s.sol";

contract OrderManagerV1Upgrade is OrderManagerV1UpgradeBase {
    address constant PROXY_ADDRESS = 0x601dE08A0297A2441eC7Ee3cd086635D0Cbb2775;
    address constant NEW_IMPL_ADDRESS =
        0x601dE08A0297A2441eC7Ee3cd086635D0Cbb2775;

    function run() external {
        upgrade(PROXY_ADDRESS, NEW_IMPL_ADDRESS);
    }
}
