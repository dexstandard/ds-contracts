// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../OrderManagerV1UpgradeBase.s.sol";

contract OrderManagerV1Upgrade is OrderManagerV1UpgradeBase {
    address constant PROXY_ADDRESS = 0xbed704Eb5686401D9dDA61FAEfF67B5BFe0b97d2;
    address constant NEW_IMPL_ADDRESS =
        0xbed704Eb5686401D9dDA61FAEfF67B5BFe0b97d2;

    function run() external {
        upgrade(PROXY_ADDRESS, NEW_IMPL_ADDRESS);
    }
}
