// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../src/yield/strategies/BaseStrategy.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract MockStrategyV1 is BaseStrategy {
    uint256 private _balanceInStrategy;
    uint256 private _mockPoolBalance;
    string private _name;

    bool public claimCalled;
    bool public swapRewardsCalled;
    bool public chargeFeesCalled;
    bool public swapNativeCalled;
    bool public autoDepositCalled;

    function initialize(
        address[] calldata _rewards,
        Addresses calldata _addresses,
        string memory name,
        uint256 _platformFee,
        uint256 _lockDuration
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards, _platformFee, _lockDuration);
        _name = name;
    }

    function strategyName() public view override returns (string memory) {
        return _name;
    }

    function balanceOfPool() public view override returns (uint256) {
        return _mockPoolBalance;
    }

    function _deposit(uint256 amount) internal override {
        _balanceInStrategy += amount;
    }

    function _withdraw(uint256 amount) internal override {
        if (amount > _balanceInStrategy) {
            amount = _balanceInStrategy;
        }
        _balanceInStrategy -= amount;
    }

    function _emergencyWithdraw() internal override {
        _balanceInStrategy = 0;
    }

    function _claim() internal override {
        claimCalled = true;
    }

    function _swapRewardsToNative() internal override {
        swapRewardsCalled = true;
    }

    function _chargeFees() internal override {
        chargeFeesCalled = true;
    }

    // Override _swapNativeToBaseToken() to record that it was called.
    function _swapNativeToBaseToken() internal override {
        swapNativeCalled = true;
    }
}
