// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/swapper/IOnchainSwapper.sol";
import "../interfaces/common/IWrappedNative.sol";

/**
 * @title BaseStrategy
 * @notice Abstract contract that defines common logic for yield strategies.
 *         Inheritors must implement specific protocol interactions such as
 *         `_deposit`, `_withdraw`, `_emergencyWithdraw`, and `_claim`.
 *
 * @dev This contract is upgradeable via OpenZeppelin's upgradeable pattern.
 */
abstract contract BaseStrategy is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ------------------------------------------------------------------------
     *                            Errors
     * --------------------------------------------------------------------- */

    error NotStrategyManager();
    error NotVault();
    error StrategyPaused();
    error UnauthorizedOwner();
    error StrategyManagerChangeUnauthorized();
    error RewardIsBaseToken();
    error RewardIsNativeToken();

    /* ------------------------------------------------------------------------
     *                            Structs
     * --------------------------------------------------------------------- */

    /**
     * @dev Holds references to the main addresses the strategy needs.
     * @param baseToken        The main token the strategy invests and wants to grow.
     * @param nativeToken      The native token of the chain
     * @param vault            The vault contract that holds user deposits and interacts with this strategy.
     * @param swapper          The external contract that performs token swaps.
     * @param strategyManager  Strategy Manager address.
     */
    struct Addresses {
        address baseToken;
        address nativeToken;
        address vault;
        address swapper;
        address strategyManager;
    }

    struct BaseFees {
        uint256 platform;
    }

    /* ------------------------------------------------------------------------
     *                            State Variables
     * --------------------------------------------------------------------- */

    address public vault;
    address public swapper;
    address public strategyManager;

    address public baseToken;
    address public nativeToken;

    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;

    bool public harvestOnDeposit;

    /// @dev Array of reward tokens that the strategy may receive from the underlying protocol.
    address[] public rewards;

    /// @dev Minimum amounts for each token required before swapping (to save on gas/swaps).
    mapping(address => uint256) public minAmounts;

    BaseFees private baseFees;

    uint256 constant DIVISOR = 1 ether;

    /* ------------------------------------------------------------------------
     *                            Events
     * --------------------------------------------------------------------- */
    event StrategyHarvest(address indexed harvester, uint256 baseTokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 platformFees);

    event SetVault(address vault);
    event SetSwapper(address swapper);
    event SetStrategyManager(address strategyManager);

    /* ------------------------------------------------------------------------
     *                            Modifiers
     * --------------------------------------------------------------------- */

    modifier onlyStrategyManager() {
        if (msg.sender != strategyManager) revert NotStrategyManager();
        _;
    }

    modifier onlyStrategyOwner() {
        if (msg.sender != owner()) revert UnauthorizedOwner();
        _;
    }

    modifier ifNotPaused() {
        if (paused()) {
            revert StrategyPaused();
        }
        _;
    }

    /* ------------------------------------------------------------------------
     *                         Initialization Logic
     * --------------------------------------------------------------------- */

    /**
     * @dev Initializes the base strategy. Called in a child contract's initialize function.
     * @param _addresses   Struct containing the addresses the strategy depends on.
     * @param _rewards     An initial list of reward tokens.
     */
    function __BaseStrategy_init(
        Addresses memory _addresses,
        address[] memory _rewards,
        uint256 _platformFee,
        uint256 _lockDuration
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __Pausable_init();

        require(_addresses.baseToken != address(0), "Invalid baseToken");
        require(_addresses.vault != address(0), "Invalid vault");
        // require(_addresses.swapper != address(0), "Invalid swapper");
        require(_addresses.strategyManager != address(0), "Invalid strategyManager");

        baseToken = _addresses.baseToken;
        nativeToken = _addresses.nativeToken;
        vault = _addresses.vault;
        swapper = _addresses.swapper;
        strategyManager = _addresses.strategyManager;
        baseFees = BaseFees({platform: _platformFee});

        for (uint256 i; i < _rewards.length; i++) {
            addReward(_rewards[i]);
        }

        lockDuration = _lockDuration;
    }

    /* ------------------------------------------------------------------------
     *                         Abstract Functions
     * --------------------------------------------------------------------- */

    function strategyName() public view virtual returns (string memory);

    function balanceOfPool() public view virtual returns (uint256);

    function _deposit(uint256 amount) internal virtual;

    function _withdraw(uint256 amount) internal virtual;

    function _emergencyWithdraw() internal virtual;

    function _claim() internal virtual;

    /* ------------------------------------------------------------------------
     *                        Core Functions
     * --------------------------------------------------------------------- */

    function deposit() public ifNotPaused {
        uint256 baseTokenBalance = balanceOfBaseToken();

        if (baseTokenBalance > 0) {
            _deposit(baseTokenBalance);
            emit Deposit(balanceOf());
        }
    }

    /**
     * @dev Withdraws a specified amount of baseToken to the vault.
     *      Only the vault can trigger this. If the strategy doesn't have enough,
     *      it pulls from the underlying protocol.
     * @param _amount The amount of baseToken to withdraw.
     */
    function withdraw(uint256 _amount) external {
        if (msg.sender != vault) revert NotVault();

        uint256 baseTokenBalance = balanceOfBaseToken();
        if (baseTokenBalance < _amount) {
            _withdraw(_amount - baseTokenBalance);
            baseTokenBalance = balanceOfBaseToken();
        }

        if (baseTokenBalance > _amount) {
            baseTokenBalance = _amount;
        }

        IERC20(baseToken).safeTransfer(vault, baseTokenBalance);
        emit Withdraw(balanceOf());
    }

    /**
     * @dev Hook called by the vault before depositing funds. If harvestOnDeposit
     *      is set, automatically triggers a harvest.
     */
    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            if (msg.sender != vault) revert NotVault();
            _harvest(true);
        }
    }

    /**
     * @dev Claims any reward tokens from the protocol (if applicable).
     */
    function claim() external virtual {
        _claim();
    }

    function harvest() external virtual onlyStrategyManager {
        _harvest(false);
    }

    /* ------------------------------------------------------------------------
     *                       Internal Harvest Logic
     * --------------------------------------------------------------------- */

    function _harvest(bool onDeposit) internal ifNotPaused {
        _claim();

        _swapRewardsToNative();

        uint256 nativeTokenBalance = IERC20(nativeToken).balanceOf(address(this));
        if (nativeTokenBalance > minAmounts[nativeToken]) {
            _chargeFees();

            _swapNativeToBaseToken();

            uint256 baseTokenHarvested = balanceOfBaseToken();
            totalLocked = baseTokenHarvested + lockedProfit();
            lastHarvest = block.timestamp;
            uint256 nativeTokenBalance = IERC20(nativeToken).balanceOf(address(this));

            // Auto-deposit if not triggered from beforeDeposit
            if (!onDeposit) {
                deposit();
            }

            emit StrategyHarvest(msg.sender, baseTokenHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal virtual {
        for (uint256 i; i < rewards.length; ++i) {
            address token = rewards[i];

            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                // Convert raw native currency to wrapped if needed
                IWrappedNative(nativeToken).deposit{value: address(this).balance}();
            } else {
                uint256 amount = IERC20(token).balanceOf(address(this));
                if (amount > minAmounts[token]) {
                    _swap(token, nativeToken, amount);
                }
            }
        }
    }

    function _chargeFees() internal virtual {
        uint256 nativeBal = IERC20(nativeToken).balanceOf(address(this));

        uint256 platformFeeAmount = (nativeBal * baseFees.platform) / DIVISOR;
        IERC20(nativeToken).safeTransfer(strategyManager, platformFeeAmount);

        emit ChargedFees(platformFeeAmount);
    }

    function _swapNativeToBaseToken() internal virtual {
        _swap(nativeToken, baseToken);
    }

    /**
     * @dev Helper function to swap the full balance of 'tokenFrom' into 'tokenTo'.
     */
    function _swap(address tokenFrom, address tokenTo) internal {
        uint256 bal = IERC20(tokenFrom).balanceOf(address(this));
        _swap(tokenFrom, tokenTo, bal);
    }

    function _swap(address tokenFrom, address tokenTo, uint256 amount) internal {
        if (tokenFrom != tokenTo && amount > 0) {
            IERC20(tokenFrom).forceApprove(swapper, amount);
            IOnchainSwapper(swapper).swap(tokenFrom, tokenTo, amount);
        }
    }

    /* ------------------------------------------------------------------------
     *                       Fee Configuration
     * --------------------------------------------------------------------- */

    function setFees(uint256 _platform) external onlyStrategyOwner {
        baseFees = BaseFees(_platform);
    }

    function getBaseFees() public view returns (BaseFees memory) {
        return baseFees;
    }

    /* ------------------------------------------------------------------------
     *                       Reward Management
     * --------------------------------------------------------------------- */

    function addReward(address _token) public onlyStrategyManager {
        if (_token == baseToken) revert RewardIsBaseToken();
        if (_token == nativeToken) revert RewardIsNativeToken();

        rewards.push(_token);
    }

    function rewardsLength() external view returns (uint256) {
        return rewards.length;
    }

    /**
     * @dev Removes a reward token from the list by index.
     */
    function removeReward(uint256 i) external onlyStrategyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    /**
     * @dev Clears all reward tokens from the list.
     */
    function resetRewards() external onlyStrategyManager {
        delete rewards;
    }

    /**
     * @dev Sets the minimum amount that must be reached before swapping.
     */
    function setRewardMinAmount(address token, uint256 minAmount) external onlyStrategyManager {
        minAmounts[token] = minAmount;
    }

    /* ------------------------------------------------------------------------
     *                          Strategy State Functions
     * --------------------------------------------------------------------- */

    /**
     * @dev Returns the current locked profit, which is a portion of harvested
     *      profit that becomes available gradually.
     */
    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return (totalLocked * remaining) / lockDuration;
    }

    /**
     * @dev Returns the total value in baseToken that the strategy controls.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfBaseToken() + balanceOfPool() - lockedProfit();
    }

    /**
     * @dev Returns how many baseTokens sit idle in this strategy contract.
     */
    function balanceOfBaseToken() public view returns (uint256) {
        return IERC20(baseToken).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyStrategyManager {
        harvestOnDeposit = _harvestOnDeposit;
        lockDuration = _harvestOnDeposit ? 0 : 1 days;
    }

    /**
     * @dev Adjusts the lock duration for partial release of harvested profit.
     * @param _duration Number of seconds for the lock.
     */
    function setLockDuration(uint256 _duration) external onlyStrategyManager {
        lockDuration = _duration;
    }

    /* ------------------------------------------------------------------------
     *                            Emergency Functions
     * --------------------------------------------------------------------- */

    /**
     * @dev Called as part of strategy migration. Withdraws all from the protocol
     *      and transfers any idle baseToken to the vault.
     */
    function retireStrategy() external {
        if (msg.sender != vault) revert NotVault();
        _emergencyWithdraw();
        IERC20(baseToken).safeTransfer(vault, balanceOfBaseToken());
    }

    /**
     * @dev Pauses the strategy and withdraws everything from the protocol.
     */
    function panic() public virtual onlyStrategyManager {
        pause();
        _emergencyWithdraw();
    }

    /**
     * @dev Pauses the strategy, preventing deposits/harvest, but allowing withdrawals.
     */
    function pause() public virtual onlyStrategyManager {
        _pause();
    }

    /**
     * @dev Unpauses the strategy and reinvests any idle baseToken.
     */
    function unpause() external virtual onlyStrategyManager {
        _unpause();
        deposit();
    }

    /* ------------------------------------------------------------------------
     *                           Owner Setters
     * --------------------------------------------------------------------- */

    /**
     * @dev Updates the vault address. Restricted to the contract owner.
     * @param _vault The new vault address.
     */
    function setVault(address _vault) external onlyStrategyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    /**
     * @dev Updates the swapper address. Restricted to the contract owner.
     * @param _swapper The new swapper contract address.
     */
    function setSwapper(address _swapper) external onlyStrategyOwner {
        swapper = _swapper;
        emit SetSwapper(_swapper);
    }

    function setStrategyManager(address _strategyManager) external onlyStrategyOwner {
        strategyManager = _strategyManager;
        emit SetStrategyManager(_strategyManager);
    }

    receive() external payable {}

    uint256[49] private __gap;
}
