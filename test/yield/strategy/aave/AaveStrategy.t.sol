// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultMultiStrategy} from "../../../../src/yield/vault/Vault.sol";
import {StrategyAaveV3Supply} from "../../../../src/yield/strategies/aave/StrategyAaveV3Supply.sol";
import {BaseStrategy} from "../../../../src/yield/strategies/BaseStrategy.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockAavePool} from "./mock/MockAavePool.t.sol";
import {MockAaveToken} from "./mock/MockAaveToken.t.sol";
import {MockOnchainSwapper} from "./mock/MockOnchainSwapper.t.sol";
import {MockAaveIncentives} from "./mock/MockAaveIncentives.t.sol";

contract StrategyAaveV3SupplyDepositTest is Test {
    address public owner = address(this);
    address public strategyManager = address(this);
    address public vault;
    address[] public rewards;
    address public user1 = address(0x0001);
    address public user2 = address(0x0002);
    uint256 platformFee = 100;
    uint256 lockDuration = 0 days;

    VaultMultiStrategy vaultContract;
    StrategyAaveV3Supply strategy;

    MockERC20 baseToken;
    MockERC20 nativeToken;
    MockERC20 rewardToken;
    MockERC20 rewardToken2;
    MockAavePool mockAavePool;
    MockAaveIncentives mockAaveIncentives;
    MockAaveToken mockAaveToken;

    function _deployVault() internal returns (VaultMultiStrategy) {
        VaultMultiStrategy implementation = new VaultMultiStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), owner, bytes(""));

        return VaultMultiStrategy(address(proxy));
    }

    function _deployStrategy() internal returns (StrategyAaveV3Supply) {
        StrategyAaveV3Supply strategyImpl = new StrategyAaveV3Supply();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(strategyImpl), owner, bytes(""));

        StrategyAaveV3Supply strategy = StrategyAaveV3Supply(payable(proxy));

        return strategy;
    }

    function setUp() external {
        baseToken = new MockERC20("WETH", "WETH");
        nativeToken = new MockERC20("ETH2", "ETH2");
        rewardToken = new MockERC20("REWARD", "REW");
        rewardToken2 = new MockERC20("REWARDToken2", "REW2");
        baseToken.mint(user1, 1_000 ether);
        baseToken.mint(user2, 1_000 ether);
        mockAaveIncentives = new MockAaveIncentives();
        MockOnchainSwapper mockOnchainSwapper = new MockOnchainSwapper();

        mockAaveToken = new MockAaveToken();
        mockAaveToken.initialize("Mock AToken", "MATK", address(baseToken), address(mockAaveIncentives));

        mockAavePool = new MockAavePool(address(mockAaveToken));

        mockAaveToken.setPool(address(mockAavePool));

        vaultContract = _deployVault();

        vault = address(vaultContract);

        strategy = _deployStrategy();

        BaseStrategy.Addresses memory addresses = BaseStrategy.Addresses({
            baseToken: address(baseToken),
            nativeToken: address(nativeToken),
            vault: vault,
            swapper: address(mockOnchainSwapper),
            strategyManager: strategyManager
        });

        rewards.push(address(rewardToken));
        rewards.push(address(rewardToken2));

        strategy.initialize(address(mockAaveToken), false, rewards, addresses, platformFee, lockDuration);
        vaultContract.initialize(
            address(baseToken), address(strategy), strategyManager, mockAaveToken.name(), mockAaveToken.symbol()
        );

        assertEq(vaultContract.activeStrategy(), address(strategy));
        assertEq(strategy.strategyName(), "Aave V3 supply");
    }

    function testDeposit() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vaultContract.deposit(amount);
        vm.stopPrank();

        assertEq(vaultContract.balance(), 100 ether, "Vault balance is incorrect");

        uint256 suppliedAmount = mockAavePool.supplied(address(baseToken));
        assertEq(suppliedAmount, 100 ether, "pool did not record the supply correctly");

        assertEq(strategy.balanceOfBaseToken(), 0, "balance of base token should be 0");
        assertEq(strategy.balanceOf(), 100 ether, "balance of the strategy should be 100");
        assertEq(strategy.balanceOfPool(), 100 ether, "balance of strategy pool should be 100");
        assertEq(strategy.lockedProfit(), 0 ether, "balance of strategy locked profit should be 0");

        assertEq(mockAaveToken.balanceOf(address(strategy)), 100 ether, "aave token balance mismatched");
        assertEq(vaultContract.balanceOf(address(user1)), 100 ether, "vault token shares mismatched");
    }

    function testDepositMultipleUsers() external {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount1);

        vaultContract.deposit(amount1);
        vm.stopPrank();

        assertEq(vaultContract.balance(), 100 ether, "Vault balance is incorrect");

        uint256 suppliedAmount = mockAavePool.supplied(address(baseToken));
        assertEq(suppliedAmount, 100 ether, "pool did not record the supply correctly");

        assertEq(strategy.balanceOfBaseToken(), 0, "balance of base token should be 0");
        assertEq(strategy.balanceOf(), 100 ether, "balance of the strategy should be 100");
        assertEq(strategy.balanceOfPool(), 100 ether, "balance of strategy pool should be 100");
        assertEq(strategy.lockedProfit(), 0 ether, "balance of strategy locked profit should be 0");

        assertEq(mockAaveToken.balanceOf(address(strategy)), 100 ether, "aave token balance mismatched");
        assertEq(vaultContract.balanceOf(address(user1)), 100 ether, "vault token shares mismatched");

        vm.startPrank(user2);
        baseToken.approve(address(vault), amount2);

        vaultContract.deposit(amount2);
        vm.stopPrank();

        assertEq(vaultContract.balance(), 150 ether, "Vault balance is incorrect");

        suppliedAmount = mockAavePool.supplied(address(baseToken));
        assertEq(suppliedAmount, 150 ether, "pool did not record the supply correctly");

        assertEq(strategy.balanceOfBaseToken(), 0, "balance of base token should be 0");
        assertEq(strategy.balanceOf(), 150 ether, "balance of the strategy should be 150");
        assertEq(strategy.balanceOfPool(), 150 ether, "balance of strategy pool should be 150");
        assertEq(strategy.lockedProfit(), 0 ether, "balance of strategy locked profit should be 0");

        assertEq(mockAaveToken.balanceOf(address(strategy)), 150 ether, "aave token balance mismatched");
        assertEq(vaultContract.balanceOf(address(user1)), 100 ether, "vault token shares mismatched");
        assertEq(vaultContract.balanceOf(address(user2)), 50 ether, "vault token shares mismatched");
    }

    function testWithdrawAll() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vaultContract.deposit(amount);
        vm.stopPrank();

        assertEq(vaultContract.balance(), 100 ether, "Vault balance is incorrect");

        uint256 userShares = vaultContract.balanceOf(address(user1));

        vm.startPrank(user1);

        vaultContract.withdraw(userShares);
        vm.stopPrank();

        uint256 suppliedAmount = mockAavePool.supplied(address(baseToken));
        assertEq(suppliedAmount, 0 ether, "pool did not record the supply correctly");

        assertEq(strategy.balanceOfBaseToken(), 0, "balance of base token should be 0");
        assertEq(strategy.balanceOf(), 0 ether, "balance of the strategy should be 0");
        assertEq(strategy.balanceOfPool(), 0 ether, "balance of strategy pool should be 0");
        assertEq(strategy.lockedProfit(), 0 ether, "balance of strategy locked profit should be 0");

        assertEq(mockAaveToken.balanceOf(address(strategy)), 0 ether, "aave token balance mismatched");
        assertEq(vaultContract.balanceOf(address(user1)), 0 ether, "vault token shares mismatched");
    }

    function testWithdrawPartial() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vaultContract.deposit(amount);
        vm.stopPrank();

        assertEq(vaultContract.balance(), 100 ether, "Vault balance is incorrect");

        uint256 userShares = vaultContract.balanceOf(address(user1));

        vm.startPrank(user1);

        vaultContract.withdraw(userShares / 2);
        vm.stopPrank();

        uint256 suppliedAmount = mockAavePool.supplied(address(baseToken));
        assertEq(suppliedAmount, 50 ether, "pool did not record the supply correctly");

        assertEq(strategy.balanceOfBaseToken(), 0, "balance of base token should be 0");
        assertEq(strategy.balanceOf(), 50 ether, "balance of the strategy should be 50");
        assertEq(strategy.balanceOfPool(), 50 ether, "balance of strategy pool should be 50");
        assertEq(strategy.lockedProfit(), 0 ether, "balance of strategy locked profit should be 0");

        assertEq(mockAaveToken.balanceOf(address(strategy)), 50 ether, "aave token balance mismatched");
        assertEq(vaultContract.balanceOf(address(user1)), 50 ether, "vault token shares mismatched");
    }

    function testHarvestWithPositiveNativeTokens() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vaultContract.deposit(amount);
        vm.stopPrank();

        rewardToken.mint(address(strategy), 10 ether);
        vm.startPrank(strategyManager);
        strategy.setRewardMinAmount(address(rewardToken), 1 ether);
        vm.stopPrank();

        uint256 baseBefore = baseToken.balanceOf(address(strategy));
        uint256 vaultBefore = baseToken.balanceOf(vault);

        vm.startPrank(strategyManager);
        strategy.harvest();
        vm.stopPrank();

        uint256 baseAfter = baseToken.balanceOf(address(strategy));
        uint256 nativeAfter = baseToken.balanceOf(address(strategy));
        uint256 totalStrategyBalance = strategy.balanceOf();
        uint256 poolSupplied = mockAavePool.supplied(address(baseToken));

        assertEq(baseAfter, 0, "Idle base tokens not zero after harvest");
        assertEq(nativeAfter, 0, "Idle native tokens not zero after harvest");
        assertEq(poolSupplied, 109999999999999999000, "Pool did not record correct supply after harvest");
        assertEq(totalStrategyBalance, 109999999999999999000, "Pool did not record correct supply after harvest");
    }

    function testHarvestWithZeroNativeTokens() external {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        baseToken.approve(address(vault), amount);

        vaultContract.deposit(amount);
        vm.stopPrank();

        uint256 baseBefore = baseToken.balanceOf(address(strategy));
        uint256 vaultBefore = baseToken.balanceOf(vault);

        vm.startPrank(strategyManager);
        strategy.harvest();
        vm.stopPrank();

        uint256 baseAfter = baseToken.balanceOf(address(strategy));
        uint256 nativeAfter = baseToken.balanceOf(address(strategy));
        uint256 totalStrategyBalance = strategy.balanceOf();
        uint256 poolSupplied = mockAavePool.supplied(address(baseToken));

        assertEq(baseAfter, 0, "Idle base tokens not zero after harvest");
        assertEq(nativeAfter, 0, "Idle native tokens not zero after harvest");
        assertEq(poolSupplied, 100 ether, "Pool did not record correct supply after harvest");
        assertEq(totalStrategyBalance, 100 ether, "Pool did not record correct supply after harvest");
    }

    function testChargeFeesTransfersPlatformFee() external {
        nativeToken.mint(address(strategy), 50 ether);

        vm.prank(strategyManager);
        strategy.setRewardMinAmount(address(nativeToken), 0);

        uint256 managerBalBefore = nativeToken.balanceOf(strategyManager);

        vm.prank(strategyManager);
        strategy.harvest();
        uint256 managerBalAfter = nativeToken.balanceOf(strategyManager);

        uint256 feeAmount = 50 ether * platformFee / 1e18;
        assertEq(managerBalAfter - managerBalBefore, feeAmount, "wrong fee");
    }

    function testUnpauseTriggersAutoDeposit() external {
        baseToken.mint(address(strategy), 10 ether);

        vm.prank(strategyManager);
        strategy.pause();

        assertEq(baseToken.balanceOf(address(strategy)), 10 ether);

        vm.prank(strategyManager);
        strategy.unpause();

        assertEq(baseToken.balanceOf(address(strategy)), 0, "idle base not deposited");
        assertEq(strategy.balanceOf(), 10 ether);
    }

    function testRetireStrategyTransfersIdleBase() external {
        baseToken.mint(address(strategy), 30 ether);
        strategy.deposit();

        baseToken.mint(address(strategy), 5 ether);

        uint256 vaultBalBefore = baseToken.balanceOf(address(vault));

        vm.prank(address(vault));
        strategy.retireStrategy();

        assertEq(strategy.balanceOfPool(), 0);

        assertEq(baseToken.balanceOf(address(vault)) - vaultBalBefore, 35 ether);
        assertEq(baseToken.balanceOf(address(strategy)), 0);
    }

    function testSwapAllRewardsAboveMin() public {
        rewardToken.mint(address(strategy), 50 ether);
        rewardToken2.mint(address(strategy), 60 ether);

        vm.startPrank(strategyManager);
        strategy.setRewardMinAmount(address(rewardToken), 1 ether);
        strategy.setRewardMinAmount(address(rewardToken2), 1 ether);
        vm.stopPrank();

        vm.prank(strategyManager);
        strategy.harvest();

        uint256 poolSupplied = mockAavePool.supplied(address(baseToken));
        uint256 totalStrategyBalance = strategy.balanceOf();

        assertEq(rewardToken.balanceOf(address(strategy)), 0, "rewardToken not swapped");
        assertEq(rewardToken2.balanceOf(address(strategy)), 0, "rewardToken2 not swapped");

        assertEq(nativeToken.balanceOf(address(strategy)), 0, "native not swapped");

        assertEq(poolSupplied, 109999999999999989000, "Pool did not record correct supply after harvest");
        assertEq(totalStrategyBalance, 109999999999999989000, "Strategy did not record correct balance after harvest");
    }
}
