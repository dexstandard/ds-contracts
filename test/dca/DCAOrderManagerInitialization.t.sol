// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultStrict} from "../../src/yield/vault/VaultStrict.sol";
import {StrategyAaveV3Supply} from "../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {DCAOrderManagerV1} from "../../src/dca/DCAOrderManagerV1.sol";
import {BaseStrategy} from "../../src/yield/strategies/BaseStrategy.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockAavePool} from "./mock/strategy/aave/MockAavePool.t.sol";
import {MockAaveToken} from "./mock/strategy/aave/MockAaveToken.t.sol";
import {MockOnchainSwapper} from "./mock/strategy/aave/MockOnchainSwapper.t.sol";
import {MockAaveIncentives} from "./mock/strategy/aave/MockAaveIncentives.t.sol";
import {DCAOrderManagerBaseTest} from "./DCAOrderManagerBase.t.sol";

contract DCAOrderManagerInitializationTest is DCAOrderManagerBaseTest {
    function setUp() public {
        setUpHelper();
    }

    /* -----------------------------------------------------------------------------
                                  Initialization
    ----------------------------------------------------------------------------- */

    function testInitializationCorrectly() public view {
        assertEq(dcaOrderManagerContract.owner(), owner, "owner mismatch");
        assertEq(dcaOrderManagerContract.executor(), dcaOrderManagerExecutor, "executor mismatch");
        assertEq(dcaOrderManagerContract.uniswapRouter(), address(uniswapRouter), "uniswapRouter mismatch");
        assertEq(dcaOrderManagerContract.pancakeRouter(), address(pancakeRouter), "pancakeRouter mismatch");
        assertEq(dcaOrderManagerContract.WETH_ADDRESS(), address(baseToken), "WETH address mismatch");
    }

    function testOnlyOwnerFunctionsRevertForNonOwner() public {
        // transferOwnership
        vm.startPrank(user1);
        vm.expectRevert(DCAOrderManagerV1.UnauthorizedOwner.selector);
        dcaOrderManagerContract.transferOwnership(user2);
        vm.stopPrank();

        // setExecutor
        vm.startPrank(user1);
        vm.expectRevert(DCAOrderManagerV1.UnauthorizedOwner.selector);
        dcaOrderManagerContract.setExecutor(user2);
        vm.stopPrank();

        // scheduleUpgrade
        vm.startPrank(user1);
        vm.expectRevert(DCAOrderManagerV1.UnauthorizedOwner.selector);
        dcaOrderManagerContract.scheduleUpgrade(address(user2));
        vm.stopPrank();
    }

    function testOwnerCanTransferOwnership() public {
        dcaOrderManagerContract.transferOwnership(user1);
        assertEq(dcaOrderManagerContract.owner(), user1, "ownership not transferred");

        vm.expectRevert(DCAOrderManagerV1.UnauthorizedOwner.selector);
        dcaOrderManagerContract.setExecutor(user2);
    }

    function testUpdatesExecutor() public {
        dcaOrderManagerContract.setExecutor(user2);
        assertEq(dcaOrderManagerContract.executor(), user2, "executor not updated");
    }

    function testSetExecutorZeroAddressReverts() public {
        vm.expectRevert(bytes("zero"));
        dcaOrderManagerContract.setExecutor(address(0));
    }

    function testTransferOwnershipZeroAddressReverts() public {
        vm.expectRevert(bytes("zero"));
        dcaOrderManagerContract.transferOwnership(address(0));
    }

    function testScheduleUpgradeSetsTimelock() public {
        uint256 start = block.timestamp;
        address newImpl = address(user2);

        dcaOrderManagerContract.scheduleUpgrade(newImpl);

        assertEq(dcaOrderManagerContract.upgradeImplementation(), newImpl, "impl not stored");
        assertEq(dcaOrderManagerContract.upgradeScheduledTime(), start + 2 days, "timelock incorrect");
    }
}
