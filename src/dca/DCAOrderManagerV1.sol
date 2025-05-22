// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {IV3SwapRouter as IV3UniswapSwapRouter} from "@uniswap/smart-router-contracts/interfaces/IV3SwapRouter.sol";
import {IV3PancakeSwapRouter} from "../interfaces/IV3PancakeSwapRouter.sol";

import "../IWETH.sol";
import {VaultStrict} from "../yield/vault/VaultStrict.sol";

/**
 * @title DCAOrderManagerV1
 * @dev Upgradable contract that manages Dollar‑Cost Averaging (DCA) orders.
 *      ‑ Only the designated executor can trigger swap execution.
 *      ‑ Owner‑only functions for administration and upgrades.
 *      ‑ Supports optional yield vault deposits for idle token‑in funds.
 */
contract DCAOrderManagerV1 is Initializable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* --------------------------------------------------------------------
     *                              ENUMS
     * -------------------------------------------------------------------- */
    enum DexEnum {
        Uniswap,
        Pancake
    }

    /* --------------------------------------------------------------------
     *                              STRUCTS
     * -------------------------------------------------------------------- */

    struct DCAOrder {
        address user;
        uint32 executedOrders;
        uint32 totalOrders;
        uint256 interval; // seconds between executions
        uint256 nextExecution; // timestamp when the next execution becomes valid
        address tokenIn;
        address tokenOut;
        address vault; // vault address (0 if yield is disabled)
        uint256 sharesRemaining; // vault shares still owned by this order (0 if vault is null)
        uint256 amountInRemaining; // token asset still owned by this order (0 if vault specified)
    }

    /* --------------------------------------------------------------------
     *                              STATE
     * -------------------------------------------------------------------- */
    address public owner;
    address public executor;
    address public uniswapRouter;
    address public pancakeRouter;
    address public WETH_ADDRESS;

    uint256 public upgradeScheduledTime; // 2‑day timelock
    address public upgradeImplementation;

    mapping(uint256 => DCAOrder) public orders; // orderId → order data
    mapping(uint256 => bool) public orderClosed; // true when all sub‑orders executed or cancelled

    /* --------------------------------------------------------------------
     *                              ERRORS
     * -------------------------------------------------------------------- */
    error UnauthorizedOwner();
    error UnauthorizedExecutor();
    error InvalidRouterIndex(DexEnum index);
    error OrderExists(uint256 orderId);
    error InvalidOrderSizeDetails();
    error OrderClosed(uint256 orderId);
    error OrderNotFound(uint256 orderId);
    error NotOrderOwner(uint256 orderId);
    error InsufficientAmountRemaining(uint256 remaining, uint256 requested);
    error NotReady(uint256 orderId, uint256 nextExecution);
    error AmountOutTooLow(address user, uint256 orderId, uint256 actualAmountOut, uint256 amountOutMin);
    error AllOrdersExecuted(uint256 orderId);
    error FeeTransferFailed(address executor, uint256 orderId, uint256 amountNative);
    error InvalidTokenInForVault();
    error InvalidSwapPath();
    error WithdrawFailed();
    error SwapFailed(string reason);
    error SwapFailedLowLevel(bytes data);
    error InsufficientAllowance(address token, address spender, uint256 allowance, uint256 required);

    /* --------------------------------------------------------------------
     *                              EVENTS
     * -------------------------------------------------------------------- */
    event ExecutorChanged(address indexed oldExecutor, address indexed newExecutor);
    event DCAOrderCreated(
        address indexed user, uint256 indexed orderId, uint256 totalTokenIn, address vault, uint256 shares
    );
    event DCAOrderExecuted(
        address indexed executor,
        address indexed user,
        uint256 indexed orderId,
        uint32 executionNumber,
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasRefundAndFees
    );
    event DCAOrderCancelled(address indexed user, uint256 indexed orderId, uint256 refundAmount);
    event UpgradeScheduled(address indexed newImplementation, uint256 scheduledTo);

    /* --------------------------------------------------------------------
     *                              MODIFIERS
     * -------------------------------------------------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedOwner();
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert UnauthorizedExecutor();
        _;
    }

    /* --------------------------------------------------------------------
     *                              INITIALIZER
     * -------------------------------------------------------------------- */
    function initialize(address _executor, address _uniswapRouter, address _pancakeRouter, address _wethAddress)
        public
        initializer
    {
        owner = msg.sender;
        executor = _executor;
        uniswapRouter = _uniswapRouter;
        pancakeRouter = _pancakeRouter;
        WETH_ADDRESS = _wethAddress;
    }

    /* --------------------------------------------------------------------
     *                              ORDER CREATION
     * -------------------------------------------------------------------- */

    /**
     * @notice Create a new DCA order. Caller must approve `totalTokenIn` to this contract before call.
     * @param orderId        unique order id.
     * @param tokenIn        Asset to spend.
     * @param tokenOut       Asset to buy.
     * @param totalAmountIn Amount (wei) spent on all sub‑orders.
     * @param totalOrders    Number of sub‑orders.
     * @param interval       Seconds between executions.
     * @param vault          Address of the yield vault
     * @param nextExecution  Execution time for the first order
     */
    function createOrder(
        uint256 orderId,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint32 totalOrders,
        uint256 interval,
        address vault,
        uint256 nextExecution
    ) external nonReentrant {
        _validateOrderCreation(orderId, tokenIn, totalAmountIn, totalOrders, vault);

        uint256 shares = 0;
        uint256 amountInRemaining = 0;

        if (vault != address(0)) {
            // deposit entire amount into the vault
            shares = VaultStrict(vault).depositFrom(msg.sender, totalAmountIn, address(this));
        } else {
            // pull funds from user
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), totalAmountIn);
            amountInRemaining = totalAmountIn;
        }

        orders[orderId] = DCAOrder({
            user: msg.sender,
            executedOrders: 0,
            totalOrders: totalOrders,
            interval: interval,
            nextExecution: nextExecution,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            vault: vault,
            sharesRemaining: shares, // zero if no vault
            amountInRemaining: amountInRemaining // zero if vault specified
        });

        emit DCAOrderCreated(msg.sender, orderId, totalAmountIn, vault, shares);
    }

    /* --------------------------------------------------------------------
     *                              ORDER EXECUTION
     * -------------------------------------------------------------------- */
    function executeOrder(
        uint256 orderId,
        bytes calldata swapPath, // main swap info
        uint256 swapAmountOutMinimum, // main swap info
        bytes calldata feePath, // fee swap info
        uint256 feeAmountOutMinimum, // fee swap info
        uint256 feeAmountIn, // fee swap info
        DexEnum dexIndex
    ) external nonReentrant onlyExecutor {
        DCAOrder storage order = orders[orderId];

        _validateOrderExecution(order, orderId);

        uint256 spendAmount = _prepareSpendAmountForOrder(order);

        _prepareForSwap(order, spendAmount, dexIndex);

        uint256 swapAmountIn = spendAmount - feeAmountIn;

        uint256 amountOut = _executeSwapForUser(order, orderId, swapAmountIn, swapAmountOutMinimum, swapPath, dexIndex);
        uint256 gasRefundAndFees =
            _takeExecutionFee(order, orderId, feeAmountIn, feeAmountOutMinimum, feePath, dexIndex);

        order.executedOrders += 1;
        order.nextExecution += order.interval;

        if (order.executedOrders == order.totalOrders) {
            orderClosed[orderId] = true;
        }

        emit DCAOrderExecuted(
            msg.sender, order.user, orderId, order.executedOrders, spendAmount, amountOut, gasRefundAndFees
        );
    }

    /* --------------------------------------------------------------------
     *                              SWAP FLOW
     * -------------------------------------------------------------------- */

    function _prepareForSwap(DCAOrder storage order, uint256 amountIn, DexEnum dexIndex) internal {
        address router = _getRouter(dexIndex);
        IERC20 token = IERC20(order.tokenIn);

        SafeERC20.forceApprove(token, router, amountIn);
        uint256 allowance = token.allowance(address(this), router);

        if (allowance < amountIn) {
            revert InsufficientAllowance(address(token), router, allowance, amountIn);
        }
    }

    function _takeExecutionFee(
        DCAOrder storage order,
        uint256 orderId,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        DexEnum dexIndex
    ) internal returns (uint256) {
        uint256 amountOfFee = amountOutMinimum;

        if (path.length == 0) return 0;

        if (order.tokenIn != WETH_ADDRESS) {
            amountOfFee = _executeSwap(address(this), amountIn, amountOutMinimum, path, dexIndex);
        }

        uint256 wethBalance = IERC20(WETH_ADDRESS).balanceOf(address(this));
        if (wethBalance == 0) return 0;

        IWETH(WETH_ADDRESS).withdraw(amountOfFee);

        uint256 contractNativeBalance = address(this).balance;
        if (contractNativeBalance == 0) return 0;

        (bool sent,) = executor.call{value: contractNativeBalance}("");
        if (!sent) {
            revert FeeTransferFailed(executor, orderId, contractNativeBalance);
        }
        return contractNativeBalance;
    }

    function _executeSwapForUser(
        DCAOrder storage order,
        uint256 orderId,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        DexEnum dexIndex
    ) internal returns (uint256) {
        uint256 amountOut;

        if (path.length == 0) {
            revert InvalidSwapPath();
        }

        amountOut = _executeSwap(order.user, amountIn, amountOutMinimum, path, dexIndex);

        if (amountOut < amountOutMinimum) {
            revert AmountOutTooLow(order.user, orderId, amountOut, amountOutMinimum);
        }

        return amountOut;
    }

    function _executeSwap(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        DexEnum dexIndex
    ) internal returns (uint256 amountOut) {
        address router = _getRouter(dexIndex);

        if (router == uniswapRouter) {
            return _executeSwapUniswap(recipient, amountIn, amountOutMinimum, path);
        }

        if (router == pancakeRouter) {
            return _executeSwapPancake(recipient, amountIn, amountOutMinimum, path);
        }
    }

    function _executeSwapUniswap(address recipient, uint256 amountIn, uint256 amountOutMinimum, bytes calldata path)
        internal
        returns (uint256)
    {
        IV3UniswapSwapRouter swapRouter = IV3UniswapSwapRouter(uniswapRouter);

        IV3UniswapSwapRouter.ExactInputParams memory params = IV3UniswapSwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        uint256 amountOut;

        try swapRouter.exactInput(params) returns (uint256 out) {
            amountOut = out;
        } catch Error(string memory reason) {
            revert SwapFailed(reason);
        } catch (bytes memory data) {
            revert SwapFailedLowLevel(data);
        }

        return amountOut;
    }

    function _executeSwapPancake(address recipient, uint256 amountIn, uint256 amountOutMinimum, bytes calldata path)
        internal
        returns (uint256)
    {
        IV3PancakeSwapRouter swapRouter = IV3PancakeSwapRouter(pancakeRouter);

        IV3PancakeSwapRouter.ExactInputParams memory params = IV3PancakeSwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        uint256 amountOut;

        try swapRouter.exactInput(params) returns (uint256 out) {
            amountOut = out;
        } catch Error(string memory reason) {
            revert SwapFailed(reason);
        } catch (bytes memory data) {
            revert SwapFailedLowLevel(data);
        }

        return amountOut;
    }

    function _getRouter(DexEnum dex) internal view returns (address) {
        if (dex == DexEnum.Uniswap) {
            return uniswapRouter;
        } else if (dex == DexEnum.Pancake) {
            return pancakeRouter;
        }

        revert InvalidRouterIndex(dex);
    }

    /* --------------------------------------------------------------------
     *                              CANCELLATION & REFUND
     * -------------------------------------------------------------------- */
    function cancelOrder(uint256 orderId) external nonReentrant {
        DCAOrder storage order = orders[orderId];

        _validateOrderCancellation(order, orderId);

        orderClosed[orderId] = true;

        uint256 remainingOrders = (order.totalOrders - order.executedOrders);

        uint256 refundAmount;

        if (remainingOrders > 0) {
            if (address(order.vault) != address(0) && order.sharesRemaining > 0) {
                refundAmount = VaultStrict(order.vault).withdrawFrom(order.sharesRemaining, order.user, address(this));
            } else if (order.amountInRemaining > 0) {
                IERC20(order.tokenIn).safeTransfer(order.user, order.amountInRemaining);
                refundAmount = order.amountInRemaining;
            }
        }

        emit DCAOrderCancelled(order.user, orderId, refundAmount);
    }

    /* --------------------------------------------------------------------
     *                              ORDER VALIDATION
     * -------------------------------------------------------------------- */
    function _validateOrderCreation(
        uint256 orderId,
        address tokenIn,
        uint256 totalAmountIn,
        uint32 totalOrders,
        address vault
    ) internal view {
        if (orders[orderId].user != address(0)) revert OrderExists(orderId);
        if (totalAmountIn == 0 || totalOrders == 0) revert InvalidOrderSizeDetails();

        if (vault != address(0)) {
            if (VaultStrict(vault).baseToken() != tokenIn) {
                revert InvalidTokenInForVault();
            }
        }
    }

    function _validateOrderExecution(DCAOrder storage order, uint256 orderId) internal view {
        if (order.user == address(0)) revert OrderNotFound(orderId);
        if (order.executedOrders == order.totalOrders) revert AllOrdersExecuted(orderId);
        if (orderClosed[orderId]) revert OrderClosed(orderId);
        if (block.timestamp < order.nextExecution) revert NotReady(orderId, order.nextExecution);
    }

    function _validateOrderCancellation(DCAOrder storage order, uint256 orderId) internal view {
        if (order.user == address(0)) revert OrderNotFound(orderId);
        if (order.user != msg.sender && msg.sender != executor) revert NotOrderOwner(orderId);
        if (orderClosed[orderId]) revert OrderClosed(orderId);
    }

    /* --------------------------------------------------------------------
     *                              ORDER UTILS
     * -------------------------------------------------------------------- */
    function _prepareSpendAmountForOrder(DCAOrder storage order) internal returns (uint256 _spendAmount) {
        uint32 ordersToExecute = order.totalOrders - order.executedOrders;

        uint256 spendAmount;
        if (address(order.vault) != address(0)) {
            uint256 sharesToRedeem =
                ordersToExecute == 1 ? order.sharesRemaining : (order.sharesRemaining / ordersToExecute);

            if (order.sharesRemaining < sharesToRedeem) {
                revert InsufficientAmountRemaining(order.sharesRemaining, sharesToRedeem);
            }

            order.sharesRemaining -= sharesToRedeem;

            uint256 receivedAmount = VaultStrict(order.vault).withdrawFrom(sharesToRedeem, address(this), address(this));

            spendAmount = receivedAmount;
        } else {
            uint256 amountInToRedeem =
                ordersToExecute == 1 ? order.amountInRemaining : (order.amountInRemaining / ordersToExecute);

            if (order.amountInRemaining < amountInToRedeem) {
                revert InsufficientAmountRemaining(order.amountInRemaining, amountInToRedeem);
            }

            order.amountInRemaining -= amountInToRedeem;

            spendAmount = amountInToRedeem;
        }

        return spendAmount;
    }

    /* --------------------------------------------------------------------
     *                              OWNER FUNCTIONS
     * -------------------------------------------------------------------- */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function setExecutor(address newExecutor) external onlyOwner {
        require(newExecutor != address(0), "zero");
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
    }

    /* --------------------------------------------------------------------
     *                              UPGRADES (2‑day timelock)
     * -------------------------------------------------------------------- */
    function scheduleUpgrade(address _newImpl) external onlyOwner {
        upgradeImplementation = _newImpl;
        upgradeScheduledTime = block.timestamp + 2 days;
        emit UpgradeScheduled(_newImpl, upgradeScheduledTime);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(block.timestamp >= upgradeScheduledTime, "timelock");
        require(newImplementation == upgradeImplementation, "wrong impl");
    }

    receive() external payable {}

    /* --------------------------------------------------------------------
     *                              STORAGE GAP
     * -------------------------------------------------------------------- */
    uint256[50] private __gap;
}
