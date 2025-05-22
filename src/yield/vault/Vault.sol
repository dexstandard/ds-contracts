// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IStrategyV1} from "../interfaces/strategy/IStrategyV1.sol";

/**
 * @title VaultMultiStrategy
 * @notice A vault contract that can connect to different strategies
 *         for yield optimization, under the control of a strategy manager.
 */
contract VaultMultiStrategy is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /* --------------------------------------------------------------------
     *                             STATE VARIABLES
     * -------------------------------------------------------------------- */

    address public baseToken;
    address public strategyManager;
    address[] public strategies; // List of strategies the vault can use.
    address public activeStrategy;

    /* --------------------------------------------------------------------
     *                             ERRORS
     * -------------------------------------------------------------------- */
    error NotStrategyManager();

    /* --------------------------------------------------------------------
     *                             MODIFIERS
     * -------------------------------------------------------------------- */

    modifier onlyStrategyManager() {
        if (msg.sender != strategyManager) revert NotStrategyManager();

        _;
    }

    /* --------------------------------------------------------------------
     *                             EVENTS 
     * -------------------------------------------------------------------- */

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategySwitched(address indexed oldStrategy, address indexed newStrategy);
    event StrategyManagerChanged(address indexed oldManager, address indexed newManager);

    /* --------------------------------------------------------------------
     *                             INITIALIZATION 
     * -------------------------------------------------------------------- */

    /**
     * @dev Initialize the vault with a base token and strategy.
     * @param _baseToken Address of the token that the vault and strategies will handle.
     * @param _strategy The address of the strategy.
     * @param _strategyManager The address allowed to manage strategies.
     * @param _name The name of the vault token (for ERC20).
     * @param _symbol The symbol of the vault token (for ERC20).
     */
    function initialize(
        address _baseToken,
        address _strategy,
        address _strategyManager,
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        require(_baseToken != address(0), "Invalid base token");
        require(_strategy != address(0), "Invalid strategy");
        require(_strategyManager != address(0), "Invalid strategy manager");
        require(address(IStrategyV1(_strategy).baseToken()) == _baseToken, "Strategy base token mismatch");

        baseToken = _baseToken;
        strategyManager = _strategyManager;
        activeStrategy = _strategy;

        strategies.push(_strategy);
    }

    /* --------------------------------------------------------------------
     *                             CORE FUNCTIONS 
     * -------------------------------------------------------------------- */

    /**
     * @dev Returns total balance controlled by the vault (including what's in the strategy).
     */
    function balance() public view returns (uint256) {
        uint256 vaultBalance = IERC20(baseToken).balanceOf(address(this));
        uint256 strategyBalance = IStrategyV1(activeStrategy).balanceOf();

        return vaultBalance + strategyBalance;
    }

    /**
     * @dev Deposit baseToken from sender into vault, then forward to active strategy.
     * @param _amount The amount of baseToken to deposit.
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Cannot deposit zero");

        IStrategyV1(activeStrategy).beforeDeposit();

        uint256 pool = balance();

        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), _amount);

        // forward to strategy
        earn();

        uint256 afterBal = balance();
        uint256 depositAmount = afterBal - pool;

        // mint vault shares proportional to deposit
        uint256 shares = 0;

        if (totalSupply() == 0) {
            shares = depositAmount;
        } else {
            shares = (depositAmount * totalSupply()) / pool;
        }

        _mint(msg.sender, shares);
    }

    /**
     * @dev Function to send baseToken from vault to active strategy.
     */
    function earn() public {
        uint256 bal = IERC20(baseToken).balanceOf(address(this));

        if (bal > 0) {
            IERC20(baseToken).safeTransfer(activeStrategy, bal);
            IStrategyV1(activeStrategy).deposit();
        }
    }

    /**
     * @dev Withdraw user's entire share balance from the vault.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Withdraw a certain number of shares from the vault,
     *      redeeming them for baseToken from the strategy if needed.
     * @param _shares The amount of vault shares to burn.
     */
    function withdraw(uint256 _shares) public nonReentrant {
        require(_shares > 0, "Cannot withdraw zero shares");

        // calc the base token amount from shares
        uint256 totalBal = balance();
        uint256 userBal = (totalBal * _shares) / totalSupply();

        _burn(msg.sender, _shares);

        uint256 vaultBal = IERC20(baseToken).balanceOf(address(this));

        // pull from strategy if vault doesn't have enough balance
        if (vaultBal < userBal) {
            uint256 toWithdraw = userBal - vaultBal;
            IStrategyV1(activeStrategy).withdraw(toWithdraw);

            uint256 afterBal = IERC20(baseToken).balanceOf(address(this));
            uint256 diff = afterBal - vaultBal;
            if (diff < toWithdraw) {
                userBal = vaultBal + diff;
            }
        }

        // send baseToken to the user
        IERC20(baseToken).safeTransfer(msg.sender, userBal);
    }

    /**
     * @dev Returns how many baseTokens are in a single share, scaled to 1e18.
     */
    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        return _totalSupply == 0 ? 1e18 : (balance() * 1e18) / _totalSupply;
    }

    /* --------------------------------------------------------------------
     *                             STRATEGY MANAGER LOGIC 
     * -------------------------------------------------------------------- */

    /**
     * @dev Add a new strategy to the vault's strategy list.
     *      The strategy must match the vault's baseToken.
     * @param _strategy Address of the new strategy contract.
     */
    function addStrategy(address _strategy) external onlyStrategyManager {
        require(_strategy != address(0), "Invalid strategy");
        require(address(IStrategyV1(_strategy).baseToken()) == baseToken, "Strategy base token mismatch");

        strategies.push(_strategy);

        emit StrategyAdded(_strategy);
    }

    /**
     * @dev Remove a strategy from the list (only if it's not the active one).
     * @param _strategy Address of the strategy to remove.
     */
    function removeStrategy(address _strategy) external onlyStrategyManager {
        require(_strategy != activeStrategy, "Cannot remove active strategy");

        uint256 length = strategies.length;
        for (uint256 i = 0; i < length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[length - 1];
                strategies.pop();
                emit StrategyRemoved(_strategy);
                return;
            }
        }

        revert("Strategy not found");
    }

    function strategiesLength() external view returns (uint256) {
        return strategies.length;
    }

    /**
     * @dev Switch the vault’s active strategy to a different one from the list.
     *      Pulls all funds out of the old strategy and deposits them into the new one.
     * @param _newStrategy The strategy to become active.
     */
    function switchStrategy(address _newStrategy) external onlyStrategyManager nonReentrant {
        require(_newStrategy != address(0), "Invalid strategy");
        require(_newStrategy != activeStrategy, "Already the active strategy");

        bool found;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _newStrategy) {
                found = true;
                break;
            }
        }

        require(found, "Strategy not added to vault");

        // withdraw everything from old strategy
        uint256 oldBal = IStrategyV1(activeStrategy).balanceOf();
        IStrategyV1(activeStrategy).withdraw(oldBal);

        // set the active strategy to the new one
        address oldStrategy = activeStrategy;
        activeStrategy = _newStrategy;
        emit StrategySwitched(oldStrategy, _newStrategy);

        // deposit to strategy
        earn();
    }

    /* --------------------------------------------------------------------
     *                             OWNER LOGIC 
     * -------------------------------------------------------------------- */

    /**
     * @dev Allows the owner to set a new strategy manager.
     */
    function setStrategyManager(address _strategyManager) external onlyOwner {
        require(_strategyManager != address(0), "Invalid manager address");
        emit StrategyManagerChanged(strategyManager, _strategyManager);
        strategyManager = _strategyManager;
    }

    /**
     * @dev Rescue any ERC20 tokens stuck in the vault.
     *      IMPORTANT: This should not allow rescuing the vault’s baseToken
     *      if it would break logic or user deposits.
     */
    function rescueStuckToken(address _token) external onlyOwner {
        require(_token != baseToken, "Cannot rescue base token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
