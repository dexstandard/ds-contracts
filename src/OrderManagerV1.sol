// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IWETH.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

/* --------------------------------------------------------------------
 *                             STRUCTS
 * -------------------------------------------------------------------- */
struct StopMarketOrder {
    address user;
    uint256 orderId;
    uint256 amountIn;
    address tokenIn;
    address tokenOut;
    uint256 ttl;
    uint256 amountOutMin;
    uint256 takeProfitOutMin;
    uint256 stopLossOutMin;
}

struct AmountOut {
    uint256 amountOut;
    address tokenOut;
}

/* --------------------------------------------------------------------
 *                             ERRORS
 * -------------------------------------------------------------------- */
error OrderVerificationFailed();
error SignatureAlreadyUsed();
error UnauthorizedExecutor();
error UnauthorizedOwner();
error OrderExpired();
error InvalidAmountOut();
error SwapFailed(address user, uint256 orderId, bytes result);
error AmountOutTooLow(address user, uint256 orderId, uint256 actualAmountOut, uint256 amountOutMin);
error FeeTransferFailed(address executor, uint256 orderId, uint256 amountNative);
error OpenOrderNotFound(uint256 orderId);

/* --------------------------------------------------------------------
 *                             ORDER MANAGER V1
 * -------------------------------------------------------------------- */
contract OrderManagerV1 is ReentrancyGuard, Initializable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /* --------------------------------------------------------------------
     *                             TIME LOCK VARIABLES
     * -------------------------------------------------------------------- */
    uint256 public upgradeScheduledTime;
    address public upgradeImplementation;

    /* --------------------------------------------------------------------
     *                             STATE VARIABLES
     * -------------------------------------------------------------------- */
    bytes32 public DOMAIN_SEPARATOR;
    address public WETH_ADDRESS;
    address public owner;
    address public uniswapRouter;

    /* the address of relayer service that is allowed to execute orders and take execution fees */
    address public executor;

    /* tracks order execution */
    mapping(address => mapping(uint256 => bool)) internal positionOpened;
    mapping(address => mapping(uint256 => bool)) internal positionClosed;

    /* tracks the amount out for closing positions */
    mapping(uint256 => AmountOut) public amountsOut;

    /* --------------------------------------------------------------------
     *                             CONSTANTS
     * -------------------------------------------------------------------- */
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "StopMarketOrder(address user,uint256 orderId,uint256 amountIn,address tokenIn,address tokenOut,uint256 ttl,uint256 amountOutMin,uint256 takeProfitOutMin,uint256 stopLossOutMin)"
    );

    /* --------------------------------------------------------------------
     *                             EVENTS
     * -------------------------------------------------------------------- */
    event ExecutorChanged(address indexed oldExecutor, address indexed newExecutor);
    event OpenOrderExecuted(
        address indexed executor,
        address indexed user,
        uint256 orderId,
        uint256 amountOut,
        address tokenOut,
        /* includes gas refund to executor and execution fees */
        uint256 gasRefundAndFees
    );
    event TakeProfitExecuted(
        address indexed executor,
        address indexed user,
        uint256 orderId,
        uint256 amountOut,
        address tokenOut,
        /* includes gas refund to executor and execution fees */
        uint256 gasRefundAndFees
    );
    event StopLossExecuted(
        address indexed executor,
        address indexed user,
        uint256 orderId,
        uint256 amountOut,
        address tokenOut,
        uint256 gasRefundAndFees
    );
    event UpgradeScheduled(address indexed newImplementation, uint256 scheduledTo);

    /* --------------------------------------------------------------------
     *                             INITIALIZER
     * -------------------------------------------------------------------- */
    function initialize(address _executor, address _uniswapRouter, address _wethAddress) public initializer {
        owner = msg.sender; // Set the deployer as the initial owner
        executor = _executor;
        uniswapRouter = _uniswapRouter;
        WETH_ADDRESS = _wethAddress;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("OrderManagerV1"), // Contract name
                keccak256("1"), // Version
                block.chainid, // Chain ID
                address(this) // Verifying contract
            )
        );
    }

    /* --------------------------------------------------------------------
     *                             UPGRADES
     * -------------------------------------------------------------------- */

    /**
     * @dev Schedule an upgrade. Only callable by the owner.
     * @param _upgradeImplementation The address of the new implementation contract.
     */
    function scheduleUpgrade(address _upgradeImplementation) external onlyOwner {
        upgradeImplementation = _upgradeImplementation;
        upgradeScheduledTime = block.timestamp + 2 days;
        emit UpgradeScheduled(_upgradeImplementation, upgradeScheduledTime);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(block.timestamp >= upgradeScheduledTime, "Upgrade still locked");
        require(upgradeImplementation == newImplementation, "Invalid upgrade");
    }

    /* --------------------------------------------------------------------
     *                          OPEN POSITION
     * -------------------------------------------------------------------- */

    /**
     * @dev Execute an order by verifying the signature.
     * @param order The order to execute.
     * @param v The recovery id (v) of the signature.
     * @param r The r parameter of the signature.
     * @param s The s parameter of the signature.
     */
    function executeOrder(
        StopMarketOrder calldata order,
        bytes calldata swapData,
        bytes calldata feeSwapData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant onlyExecutor {
        _verifySignature(order, v, r, s);
        _markPositionOpened(order.user, order.orderId);
        _validateOrder(order.ttl, order.amountOutMin);
        _prepareForSwap(order);
        uint256 actualAmountOut = _executeSwapForUser(order, swapData);
        uint256 gasRefundAndFees = _takeExecutionFee(order.user, order.orderId, order.tokenIn, feeSwapData);
        emit OpenOrderExecuted(executor, order.user, order.orderId, actualAmountOut, order.tokenOut, gasRefundAndFees);
    }

    /* --------------------------------------------------------------------
     *                          TAKE PROFIT
     * -------------------------------------------------------------------- */

    /**
     * @dev IMPORTANT: Token OUT used as Token IN for the take profit order.
     */
    function executeTakeProfit(
        StopMarketOrder calldata order,
        bytes calldata swapData,
        bytes calldata feeSwapData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant onlyExecutor {
        _verifySignature(order, v, r, s);
        _checkPositionOpened(order.user, order.orderId);
        _markPositionClosed(order.user, order.orderId);
        _validateOrder(order.ttl, order.takeProfitOutMin);

        (uint256 openOrderAmountOut, address openOrderTokenOut) = getAmountOut(order.orderId);
        _prepareForSwap(order.user, openOrderTokenOut, openOrderAmountOut);

        uint256 actualAmountOut =
            _executeClosePositionSwap(order.user, order.orderId, swapData, order.tokenIn, order.takeProfitOutMin);
        uint256 gasRefundAndFees = _takeExecutionFee(order.user, order.orderId, order.tokenOut, feeSwapData);

        emit TakeProfitExecuted(executor, order.user, order.orderId, actualAmountOut, order.tokenIn, gasRefundAndFees);
    }

    /* --------------------------------------------------------------------
     *                          STOP LOSS
     * -------------------------------------------------------------------- */
    function executeStopLoss(
        StopMarketOrder calldata order,
        bytes calldata swapData,
        bytes calldata feeSwapData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant onlyExecutor {
        _verifySignature(order, v, r, s);
        _checkPositionOpened(order.user, order.orderId);
        _markPositionClosed(order.user, order.orderId);
        _validateOrder(order.ttl, order.stopLossOutMin);
        (uint256 openOrderAmountOut, address openOrderTokenOut) = getAmountOut(order.orderId);
        _prepareForSwap(order.user, openOrderTokenOut, openOrderAmountOut);

        uint256 actualAmountOut =
            _executeClosePositionSwap(order.user, order.orderId, swapData, order.tokenIn, order.stopLossOutMin);
        uint256 gasRefundAndFees = _takeExecutionFee(order.user, order.orderId, order.tokenOut, feeSwapData);

        emit StopLossExecuted(executor, order.user, order.orderId, actualAmountOut, order.tokenIn, gasRefundAndFees);
    }

    /* --------------------------------------------------------------------
     *                         HELPER FUNCTIONS
     * -------------------------------------------------------------------- */

    /**
     * @dev Verifies the validity of the digest and the signature for an order.
     * Reverts if verification fails.
     * @param order The order to verify.
     * @param v The recovery id (v) of the signature.
     * @param r The r parameter of the signature.
     * @param s The s parameter of the signature.
     */
    function _verifySignature(StopMarketOrder calldata order, uint8 v, bytes32 r, bytes32 s) internal view {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01", // EIP-191 prefix
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        ORDER_TYPEHASH,
                        order.user,
                        order.orderId,
                        order.amountIn,
                        order.tokenIn,
                        order.tokenOut,
                        order.ttl,
                        order.amountOutMin,
                        order.takeProfitOutMin,
                        order.stopLossOutMin
                    )
                )
            )
        );
        address recoveredSigner = digest.recover(v, r, s);
        if (recoveredSigner != order.user) {
            revert OrderVerificationFailed();
        }
    }

    function _checkPositionOpened(address user, uint256 orderId) internal view {
        if (!positionOpened[user][orderId]) revert OpenOrderNotFound(orderId);
    }

    function _markPositionOpened(address user, uint256 orderId) internal {
        if (positionOpened[user][orderId]) revert SignatureAlreadyUsed();
        positionOpened[user][orderId] = true;
    }

    function _markPositionClosed(address user, uint256 orderId) internal {
        if (positionClosed[user][orderId]) revert SignatureAlreadyUsed();
        positionClosed[user][orderId] = true;
    }

    function _validateOrder(uint256 ttl, uint256 amountOutMin) internal view {
        if (block.timestamp > ttl) revert OrderExpired();
        if (amountOutMin == 0) revert InvalidAmountOut();
    }

    function _prepareForSwap(address user, address tokenIn, uint256 amountIn) internal {
        IERC20(tokenIn).safeTransferFrom(user, address(this), amountIn);
        SafeERC20.forceApprove(IERC20(tokenIn), uniswapRouter, amountIn);
    }

    function _prepareForSwap(StopMarketOrder calldata order) internal {
        IERC20(order.tokenIn).safeTransferFrom(order.user, address(this), order.amountIn);
        SafeERC20.forceApprove(IERC20(order.tokenIn), uniswapRouter, order.amountIn);
    }

    function _takeExecutionFee(address user, uint256 orderId, address tokenIn, bytes calldata feeSwapData)
        internal
        returns (uint256)
    {
        if (feeSwapData.length == 0) return 0;

        if (tokenIn != WETH_ADDRESS) {
            _executeSwap(user, orderId, feeSwapData);
        }

        uint256 wethBalance = IERC20(WETH_ADDRESS).balanceOf(address(this));
        if (wethBalance == 0) return 0;

        IWETH(WETH_ADDRESS).withdraw(wethBalance);
        uint256 contractNativeBalance = address(this).balance;
        if (contractNativeBalance == 0) return 0;

        (bool sent,) = executor.call{value: contractNativeBalance}("");
        if (!sent) {
            revert FeeTransferFailed(executor, orderId, contractNativeBalance);
        }
        return contractNativeBalance;
    }

    function _executeSwapForUser(StopMarketOrder calldata order, bytes calldata swapData) internal returns (uint256) {
        uint256 balanceBefore = IERC20(order.tokenOut).balanceOf(order.user);
        _executeSwap(order.user, order.orderId, swapData);
        uint256 actualAmountOut = _validateUserBalance(order, balanceBefore);
        amountsOut[order.orderId] = AmountOut(actualAmountOut, order.tokenOut);
        return actualAmountOut;
    }

    function _executeClosePositionSwap(
        address user,
        uint256 orderId,
        bytes calldata swapData,
        address tokenOut,
        uint256 minOut
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(user);
        _executeSwap(user, orderId, swapData);
        return _validateUserBalance(user, orderId, balanceBefore, tokenOut, minOut);
    }

    function _executeSwap(address user, uint256 orderId, bytes calldata swapData) internal {
        (bool success, bytes memory result) = uniswapRouter.call(swapData);
        if (!success) revert SwapFailed(user, orderId, result);
    }

    function _validateUserBalance(StopMarketOrder calldata order, uint256 balanceBefore)
        internal
        view
        returns (uint256)
    {
        return _validateUserBalance(order.user, order.orderId, balanceBefore, order.tokenOut, order.amountOutMin);
    }

    function _validateUserBalance(
        address user,
        uint256 orderId,
        uint256 balanceBefore,
        address tokenOut,
        uint256 amountOutMin
    ) internal view returns (uint256) {
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(user);
        uint256 actualAmountOut = balanceAfter - balanceBefore;
        if (actualAmountOut < amountOutMin) {
            revert AmountOutTooLow(user, orderId, actualAmountOut, amountOutMin);
        }
        return actualAmountOut;
    }

    /* --------------------------------------------------------------------
     *                          OWNER MANAGEMENT
     * -------------------------------------------------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }

    /**
     * @dev Updates the executor address. Only callable by the owner.
     * @param newExecutor The address of the new executor.
     */
    function setExecutor(address newExecutor) external onlyOwner {
        require(newExecutor != address(0), "Invalid executor address");
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert UnauthorizedExecutor();
        _;
    }

    function getAmountOut(uint256 orderId) public view returns (uint256, address) {
        AmountOut storage data = amountsOut[orderId];
        if (data.amountOut == 0) revert OpenOrderNotFound(orderId);
        return (data.amountOut, data.tokenOut);
    }

    receive() external payable {}

    /* --------------------------------------------------------------------
     *                          STORAGE GAP
     * -------------------------------------------------------------------- */
    uint256[50] private __gap;
}
