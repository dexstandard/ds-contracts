// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPool} from "@aaveV3/interfaces/IPool.sol";
import {AToken} from "@aaveV3/protocol/tokenization/AToken.sol";

import "../../interfaces/aave/IAaveV3Incentives.sol";
import "../BaseStrategy.sol";

contract StrategyAaveV3Supply is BaseStrategy {
    using SafeERC20 for IERC20;

    address public aToken;
    address public pool;
    address public incentivesController;

    function initialize(
        address _aToken,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses,
        uint256 _platformFee,
        uint256 _lockDuration
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards, _platformFee, _lockDuration);

        aToken = _aToken;
        pool = address(AToken(aToken).POOL());
        baseToken = AToken(aToken).UNDERLYING_ASSET_ADDRESS();
        incentivesController = address(AToken(aToken).getIncentivesController());

        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function strategyName() public pure override returns (string memory) {
        return "Aave V3 supply";
    }

    function balanceOfPool() public view override returns (uint256) {
        return IERC20(aToken).balanceOf(address(this));
    }

    function _deposit(uint256 amount) internal override {
        IERC20(baseToken).forceApprove(pool, amount);

        IPool(pool).supply(baseToken, amount, address(this), 0);
    }

    function _withdraw(uint256 amount) internal override {
        if (amount > 0) {
            IPool(pool).withdraw(baseToken, amount, address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        uint256 amount = balanceOfPool();
        if (amount > 0) {
            IPool(pool).withdraw(baseToken, type(uint256).max, address(this));
        }
    }

    function _claim() internal override {
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        IAaveV3Incentives(incentivesController).claimAllRewards(assets, address(this));
    }
}
