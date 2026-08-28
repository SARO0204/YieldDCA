// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDCAStrategy
 * @notice Interface defining the core data types, custom errors, events, and external API
 *         for Module 1 (DCA Strategy Management) of the Yield-Aware DCA system.
 * @dev Module 1 is strictly responsible for strategy lifecycle management, parameter storage,
 *      and execution constraint validation. It does NOT move funds, execute swaps, or calculate
 *      market intelligence.
 */
interface IDCAStrategy {
    // ------------------------------------------------------------------------
    // ENUMS & STRUCTS
    // ------------------------------------------------------------------------

    /**
     * @notice Represents the operational lifecycle status of a DCA strategy.
     * @custom:value NONE Uninitialized or non-existent strategy.
     * @custom:value ACTIVE Strategy is active and eligible for execution scheduling.
     * @custom:value PAUSED Strategy is temporarily paused by its owner.
     * @custom:value CANCELLED Strategy is permanently cancelled by its owner.
     * @custom:value COMPLETED Reserved for future execution/accounting modules; Module 1 never sets this.
     */
    enum StrategyStatus {
        NONE,
        ACTIVE,
        PAUSED,
        CANCELLED,
        COMPLETED
    }

    /**
     * @notice Complete persistent storage model for a user's DCA strategy.
     * @param owner Address of the user who created and manages this strategy (Immutable).
     * @param inputToken Address of the ERC-20 token being invested/sold (Immutable).
     * @param targetToken Address of the ERC-20 token being acquired/bought (Immutable).
     * @param targetAllocation Configured target allocation for the DCA cycle (User-Modifiable).
     * @param frequency Interval in seconds between scheduled executions (User-Modifiable).
     * @param maxDelay Maximum allowed delay in seconds past nextExecutionTime (User-Modifiable, > 0).
     * @param minExecutionAmount Minimum allowed amount per execution order (User-Modifiable).
     * @param maxExecutionAmount Maximum allowed amount per execution order (User-Modifiable).
     * @param nextExecutionTime Timestamp when the strategy is next scheduled for execution.
     * @param status Current lifecycle status of the strategy.
     */
    struct Strategy {
        address owner;
        address inputToken;
        address targetToken;
        uint256 targetAllocation;
        uint256 frequency;
        uint256 maxDelay;
        uint256 minExecutionAmount;
        uint256 maxExecutionAmount;
        uint256 nextExecutionTime;
        StrategyStatus status;
    }

    /**
     * @notice Parameters required to create a new DCA strategy.
     * @param inputToken Address of the token to sell (cannot be zero address).
     * @param targetToken Address of the token to buy (cannot be zero address, must != inputToken).
     * @param targetAllocation Desired capital allocation target for the DCA cycle (> 0).
     * @param frequency Cadence in seconds between executions (> 0).
     * @param maxDelay Maximum permitted delay window after nextExecutionTime in seconds (> 0).
     * @param minExecutionAmount Minimum permissible execution amount (> 0).
     * @param maxExecutionAmount Maximum permissible execution amount (>= minExecutionAmount, <= targetAllocation).
     * @param firstExecutionTime Scheduled start timestamp (0 defaults to block.timestamp; if > 0, must be >= block.timestamp).
     */
    struct StrategyParams {
        address inputToken;
        address targetToken;
        uint256 targetAllocation;
        uint256 frequency;
        uint256 maxDelay;
        uint256 minExecutionAmount;
        uint256 maxExecutionAmount;
        uint256 firstExecutionTime;
    }

    // ------------------------------------------------------------------------
    // CUSTOM ERRORS
    // ------------------------------------------------------------------------

    error ZeroAddressInputToken();
    error ZeroAddressTargetToken();
    error IdenticalTokens(address token);
    error ZeroTargetAllocation();
    error ZeroFrequency();
    error ZeroMinExecutionAmount();
    error ZeroMaxExecutionAmount();
    error ZeroMaxDelay();
    error MinExecutionExceedsMax(uint256 minAmount, uint256 maxAmount);
    error MaxExecutionExceedsAllocation(uint256 maxAmount, uint256 targetAllocation);
    error MinExecutionExceedsAllocation(uint256 minAmount, uint256 targetAllocation);
    error InvalidFirstExecutionTime(uint256 firstExecutionTime, uint256 currentTimestamp);
    error StrategyNotFound(uint256 strategyId);
    error NotStrategyOwner(uint256 strategyId, address caller, address owner);
    error InvalidStrategyStatus(uint256 strategyId, StrategyStatus currentStatus, StrategyStatus expectedStatus);
    error StrategyAlreadyCancelled(uint256 strategyId);
    error StrategyInactive(uint256 strategyId, StrategyStatus currentStatus);

    // ------------------------------------------------------------------------
    // EVENTS
    // ------------------------------------------------------------------------

    event StrategyCreated(
        uint256 indexed strategyId,
        address indexed owner,
        address indexed inputToken,
        address targetToken,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount,
        uint256 firstExecutionTime
    );

    event StrategyUpdated(
        uint256 indexed strategyId,
        address indexed owner,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    );

    event StrategyPaused(uint256 indexed strategyId, address indexed owner);
    event StrategyResumed(uint256 indexed strategyId, address indexed owner);
    event StrategyCancelled(uint256 indexed strategyId, address indexed owner);

    // ------------------------------------------------------------------------
    // STRATEGY LIFECYCLE MANAGEMENT (MUTATING)
    // ------------------------------------------------------------------------

    /**
     * @notice Creates a new DCA strategy.
     * @param params Configuration parameters for the new strategy.
     * @return strategyId The unique monotonically increasing identifier of the created strategy.
     */
    function createStrategy(StrategyParams calldata params) external returns (uint256 strategyId);

    /**
     * @notice Updates configuration parameters of an existing strategy.
     * @dev Only callable by the strategy owner. Strategy must be ACTIVE or PAUSED.
     *      Token addresses and owner are immutable.
     * @param strategyId Unique ID of the strategy to update.
     * @param targetAllocation New target allocation for the cycle.
     * @param frequency New interval between executions in seconds.
     * @param maxDelay New maximum permitted delay window in seconds (> 0).
     * @param minExecutionAmount New minimum allowed execution amount.
     * @param maxExecutionAmount New maximum allowed execution amount.
     */
    function updateStrategy(
        uint256 strategyId,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    ) external;

    /**
     * @notice Pauses an active DCA strategy.
     * @dev Only callable by the strategy owner. Reverts if strategy is not ACTIVE.
     * @param strategyId Unique ID of the strategy to pause.
     */
    function pauseStrategy(uint256 strategyId) external;

    /**
     * @notice Resumes a paused DCA strategy.
     * @dev Only callable by the strategy owner. Reverts if strategy is not PAUSED.
     * @param strategyId Unique ID of the strategy to resume.
     */
    function resumeStrategy(uint256 strategyId) external;

    /**
     * @notice Permanently cancels a DCA strategy.
     * @dev Only callable by the strategy owner. Reverts if strategy is already CANCELLED or non-existent.
     * @param strategyId Unique ID of the strategy to cancel.
     */
    function cancelStrategy(uint256 strategyId) external;

    // ------------------------------------------------------------------------
    // QUERIES & GETTERS
    // ------------------------------------------------------------------------

    /**
     * @notice Returns the full strategy struct for a given strategy ID.
     * @param strategyId Unique ID of the strategy.
     * @return strategy The strategy struct.
     */
    function getStrategy(uint256 strategyId) external view returns (Strategy memory strategy);

    /**
     * @notice Returns all strategy IDs owned by a user.
     * @param user Address of the strategy owner.
     * @return strategyIds Array of strategy IDs created by the user.
     */
    function getUserStrategies(address user) external view returns (uint256[] memory strategyIds);

    /**
     * @notice Returns total number of strategies created so far.
     * @return count Total count of created strategies.
     */
    function getStrategyCount() external view returns (uint256 count);

    // ------------------------------------------------------------------------
    // EXECUTION & SCHEDULING SUPPORT (READ-ONLY)
    // ------------------------------------------------------------------------

    /**
     * @notice Checks whether a strategy is due for execution (`block.timestamp >= nextExecutionTime`).
     * @dev Returns false if strategy is not ACTIVE.
     * @param strategyId Unique ID of the strategy.
     * @return isDue True if strategy is ACTIVE and current block timestamp is at or past nextExecutionTime.
     */
    function isExecutionDue(uint256 strategyId) external view returns (bool isDue);

    /**
     * @notice Checks whether current block timestamp falls within the permitted execution window:
     *         `nextExecutionTime <= block.timestamp <= nextExecutionTime + maxDelay`.
     * @dev Returns false if strategy is not ACTIVE.
     * @param strategyId Unique ID of the strategy.
     * @return isOpen True if strategy is ACTIVE and within the user's allowed delay window.
     */
    function isExecutionWindowOpen(uint256 strategyId) external view returns (bool isOpen);

    /**
     * @notice Checks whether a strategy is overdue past its allowed max delay window:
     *         `block.timestamp > nextExecutionTime + maxDelay`.
     * @dev Returns false if strategy is not ACTIVE.
     * @param strategyId Unique ID of the strategy.
     * @return overdue True if strategy is ACTIVE and current block timestamp exceeds nextExecutionTime + maxDelay.
     */
    function isOverdue(uint256 strategyId) external view returns (bool overdue);

    /**
     * @notice Returns remaining seconds available before the execution window expires.
     * @param strategyId Unique ID of the strategy.
     * @return remainingSeconds Remaining delay seconds in the execution window (0 if overdue).
     */
    function getRemainingDelay(uint256 strategyId) external view returns (uint256 remainingSeconds);

    /**
     * @notice Validates whether an execution amount conforms to the user's strategy constraints.
     * @dev Checks: amount > 0, amount >= minExecutionAmount, amount <= maxExecutionAmount,
     *      and amount <= targetAllocation. Strategy must be ACTIVE.
     * @param strategyId Unique ID of the strategy.
     * @param amount Proposed execution order amount.
     * @return isValid True if amount meets all strategy constraints.
     */
    function isValidExecutionAmount(uint256 strategyId, uint256 amount) external view returns (bool isValid);
}
