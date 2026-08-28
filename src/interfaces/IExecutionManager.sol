// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDecisionEngine} from "./IDecisionEngine.sol";
import {ISwapExecutor} from "./ISwapExecutor.sol";

/**
 * @title IExecutionManager
 * @notice Interface for Module 6 (orchestration) and Module 8 (atomic execution guarantees).
 * @dev Module 8 strengthens Module 6 with:
 *      - An explicit validateExecution() view for pre-flight auditing.
 *      - Full NatSpec documenting EVM transaction atomicity guarantees.
 *      - Comprehensive test coverage proving failure scenarios leave no partial state.
 * @dev The ExecutionManager is the execution/orchestration layer that bridges the
 *      DecisionEngine's recommendation and the actual capital movement.
 *
 *      Architecture:
 *
 *          DecisionEngine (Module 5)
 *                  │ DecisionResult
 *                  ▼
 *          ExecutionManager (Module 6)
 *                  │
 *         ┌────────┴─────────┐
 *         │                  │
 *      YieldVault      ISwapExecutor
 *   (withdrawForStrategy)   (executeSwap)
 *         │                  │
 *         └────────┬─────────┘
 *                  │
 *             Accounting
 *
 *      RESPONSIBILITIES:
 *      1. Validate the DecisionResult against authoritative on-chain state.
 *      2. Enforce all hard execution constraints independently.
 *      3. Withdraw the exact required capital from the YieldVault.
 *      4. Invoke the swap executor.
 *      5. Update per-strategy execution accounting.
 *      6. Emit structured execution events.
 *
 *      DOES NOT:
 *      - Make any economic decisions.
 *      - Re-score market conditions.
 *      - Query oracles or market data.
 *      - Accept user private keys.
 *
 * @custom:security-contact module6@yielddca.local
 */
interface IExecutionManager {
    // -------------------------------------------------------------------------
    // ENUMS
    // -------------------------------------------------------------------------

    /**
     * @notice Result status of an execution attempt.
     * @custom:value SUCCESS Execution completed with swap and accounting.
     * @custom:value DELAYED No capital moved; delay was the valid action.
     * @custom:value FAILED Execution was attempted but reverted (accounting unchanged).
     */
    enum ExecutionStatus {
        SUCCESS,
        DELAYED,
        FAILED
    }

    // -------------------------------------------------------------------------
    // STRUCTS
    // -------------------------------------------------------------------------

    /**
     * @notice Cumulative per-strategy execution accounting maintained by the ExecutionManager.
     * @param totalExecuted Total amount of inputToken executed across all executions for this strategy.
     * @param lastExecutionTimestamp Block timestamp of the most recent successful execution.
     * @param lastExecutionAmount Amount executed in the most recent successful execution.
     * @param executionCount Number of completed successful executions.
     * @param nonce Monotonically increasing counter preventing replay of old decisions.
     */
    struct ExecutionRecord {
        uint256 totalExecuted;
        uint256 lastExecutionTimestamp;
        uint256 lastExecutionAmount;
        uint256 executionCount;
        uint256 nonce;
    }

    /**
     * @notice Structured result returned by executeDecision.
     * @param strategyId The strategy that was processed.
     * @param status Whether execution succeeded, was delayed, or failed.
     * @param action The action taken from the DecisionResult.
     * @param requestedAmount Amount recommended by the DecisionResult.
     * @param executedAmount Actual amount of inputToken consumed in the swap (0 for DELAY).
     * @param withdrawnAmount Amount of inputToken withdrawn from the YieldVault (0 for DELAY).
     * @param swapOutputAmount Amount of targetToken received from the swap (0 for DELAY).
     * @param remainingAllocation Remaining target allocation after this execution.
     * @param timestamp Block timestamp of this execution result.
     * @param nonce Execution nonce used for this call (replay protection).
     */
    struct ExecutionResult {
        uint256 strategyId;
        ExecutionStatus status;
        IDecisionEngine.DecisionAction action;
        uint256 requestedAmount;
        uint256 executedAmount;
        uint256 withdrawnAmount;
        uint256 swapOutputAmount;
        uint256 remainingAllocation;
        uint256 timestamp;
        uint256 nonce;
    }

    // -------------------------------------------------------------------------
    // CUSTOM ERRORS
    // -------------------------------------------------------------------------

    /// @notice Caller is not authorized to execute the given strategy.
    error UnauthorizedExecutor(uint256 strategyId, address caller);

    /// @notice Strategy does not exist.
    error StrategyNotFound(uint256 strategyId);

    /// @notice Strategy is not in ACTIVE state.
    error StrategyNotActive(uint256 strategyId);

    /// @notice DecisionResult action is not one of the recognized values.
    error InvalidDecisionAction();

    /// @notice Decision timestamp is too old (stale result).
    error StaleDecision(uint256 decisionTimestamp, uint256 currentTimestamp, uint256 maxAge);

    /// @notice Requested execution amount is zero.
    error ZeroExecutionAmount(uint256 strategyId);

    /// @notice Requested amount is below the strategy's minimum execution amount.
    error BelowMinimumExecution(uint256 strategyId, uint256 amount, uint256 minimum);

    /// @notice Requested amount exceeds the strategy's maximum execution amount.
    error AboveMaximumExecution(uint256 strategyId, uint256 amount, uint256 maximum);

    /// @notice Requested amount exceeds the remaining target allocation.
    error ExceedsRemainingAllocation(uint256 strategyId, uint256 amount, uint256 remaining);

    /// @notice Vault does not hold enough assets to cover the execution.
    error InsufficientVaultFunds(uint256 strategyId, uint256 required, uint256 available);

    /// @notice Provided nonce does not match the expected next nonce.
    error InvalidNonce(uint256 strategyId, uint256 provided, uint256 expected);

    /// @notice The swap executor returned a failure result.
    error SwapExecutionFailed(uint256 strategyId, uint256 inputAmount);

    /// @notice Zero address provided where non-zero is required.
    error ZeroAddress();

    /// @notice The strategy's input token does not match the vault's underlying asset.
    error InvalidInputToken();

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when execution of a strategy's decision is requested.
     * @param strategyId Strategy identifier.
     * @param caller Address that invoked executeDecision.
     * @param action Requested action from the DecisionResult.
     * @param requestedAmount Amount requested for execution (0 for DELAY).
     * @param nonce Execution nonce for this request.
     */
    event ExecutionRequested(
        uint256 indexed strategyId,
        address indexed caller,
        IDecisionEngine.DecisionAction action,
        uint256 requestedAmount,
        uint256 nonce
    );

    /**
     * @notice Emitted after all pre-execution validations pass.
     * @param strategyId Strategy identifier.
     * @param finalAmount The validated execution amount after on-chain constraint checks.
     * @param nonce Nonce for this execution.
     */
    event ExecutionValidated(uint256 indexed strategyId, uint256 finalAmount, uint256 nonce);

    /**
     * @notice Emitted when capital is successfully withdrawn from the YieldVault.
     * @param strategyId Strategy identifier.
     * @param user Strategy owner whose vault shares were burned.
     * @param assets Amount of underlying assets withdrawn.
     * @param sharesBurned ERC-4626 shares burned to cover the withdrawal.
     */
    event CapitalWithdrawn(uint256 indexed strategyId, address indexed user, uint256 assets, uint256 sharesBurned);

    /**
     * @notice Emitted when a swap is successfully executed.
     * @param strategyId Strategy identifier.
     * @param inputConsumed Amount of inputToken consumed.
     * @param outputReceived Amount of targetToken received.
     */
    event SwapExecuted(uint256 indexed strategyId, uint256 inputConsumed, uint256 outputReceived);

    /**
     * @notice Emitted when a strategy execution is completed successfully.
     * @param strategyId Strategy identifier.
     * @param owner Strategy owner address.
     * @param executedAmount Amount of inputToken executed.
     * @param swapOutputAmount Amount of targetToken received.
     * @param remainingAllocation Remaining allocation after this execution.
     * @param nonce Nonce used for this execution.
     * @param timestamp Block timestamp.
     */
    event ExecutionCompleted(
        uint256 indexed strategyId,
        address indexed owner,
        uint256 executedAmount,
        uint256 swapOutputAmount,
        uint256 remainingAllocation,
        uint256 nonce,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a DELAY decision is processed (no capital movement).
     * @param strategyId Strategy identifier.
     * @param recommendedDelay Seconds recommended before next evaluation.
     * @param nonce Nonce advanced for this call.
     */
    event ExecutionDelayed(uint256 indexed strategyId, uint256 recommendedDelay, uint256 nonce);

    /**
     * @notice Emitted when the ExecutionManager is configured with a new swap executor.
     * @param oldExecutor Previous swap executor address.
     * @param newExecutor New swap executor address.
     */
    event SwapExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);

    // -------------------------------------------------------------------------
    // CORE EXECUTION
    // -------------------------------------------------------------------------

    /**
     * @notice Executes or processes a decision produced by Module 5's DecisionEngine.
     * @dev This is the primary entry point for Module 6.
     *      Validates the DecisionResult against live on-chain state,
     *      withdraws exact capital from the YieldVault,
     *      invokes the swap executor, and records accounting.
     *
     *      Authorization: Only the strategy owner or an authorized executor may call.
     *
     *      Replay protection: The caller must supply the expected execution nonce.
     *      Stale-decision protection: The DecisionResult.timestamp must be recent.
     *
     * @param strategyId Unique ID of the DCA strategy to execute.
     * @param decision The DecisionResult produced by the DecisionEngine for this strategy.
     * @param expectedNonce The caller's expected execution nonce (prevents replay).
     * @param minSwapOutput Minimum acceptable swap output amount (0 to disable slippage check).
     * @return result Structured result of the execution.
     */
    function executeDecision(
        uint256 strategyId,
        IDecisionEngine.DecisionResult calldata decision,
        uint256 expectedNonce,
        uint256 minSwapOutput
    ) external returns (ExecutionResult memory result);

    // -------------------------------------------------------------------------
    // ACCOUNTING & STATE QUERIES
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the execution accounting record for a strategy.
     * @param strategyId Unique ID of the strategy.
     * @return record The cumulative execution record.
     */
    function getExecutionRecord(uint256 strategyId) external view returns (ExecutionRecord memory record);

    /**
     * @notice Returns the remaining target allocation for a strategy.
     * @dev remainingAllocation = targetAllocation - totalExecuted.
     *      Returns targetAllocation if strategy has never been executed.
     * @param strategyId Unique ID of the strategy.
     * @return remaining Remaining allocation in asset units.
     */
    function getRemainingAllocation(uint256 strategyId) external view returns (uint256 remaining);

    /**
     * @notice Returns the current execution nonce for a strategy.
     * @dev The next executeDecision call must supply this value as expectedNonce.
     * @param strategyId Unique ID of the strategy.
     * @return nonce Current nonce value.
     */
    function getExecutionNonce(uint256 strategyId) external view returns (uint256 nonce);

    /**
     * @notice Module 8: Pre-flight validation of an execution request WITHOUT capital movement.
     * @dev Pure view function — reads state only, performs no transfers, no state changes.
     *      Validates all execution preconditions in the same order as executeDecision:
     *        1. Strategy exists and is ACTIVE.
     *        2. Caller is authorized.
     *        3. Nonce matches expected.
     *        4. Decision is not stale.
     *        5. Execution amount is valid (non-zero, ≥ min, ≤ max, ≤ remaining).
     *        6. Vault has sufficient underlying assets.
     *      Reverts with the same errors as executeDecision if any check fails.
     *      Useful for off-chain pre-simulation and on-chain automation checks.
     * @param strategyId Unique ID of the DCA strategy.
     * @param decision The DecisionResult to validate.
     * @param expectedNonce The caller's expected nonce.
     * @return validatedAmount The validated execution amount that will be used.
     * @return remainingAfter Remaining allocation after the proposed execution.
     */
    function validateExecution(
        uint256 strategyId,
        IDecisionEngine.DecisionResult calldata decision,
        uint256 expectedNonce
    ) external view returns (uint256 validatedAmount, uint256 remainingAfter);

    // -------------------------------------------------------------------------
    // AUTHORIZATION MANAGEMENT
    // -------------------------------------------------------------------------

    /**
     * @notice Authorizes or revokes an automation executor address per strategy.
     * @dev Only callable by the strategy owner.
     * @param strategyId Strategy identifier.
     * @param executor Address to authorize or revoke.
     * @param authorized True to authorize, false to revoke.
     */
    function setStrategyExecutor(uint256 strategyId, address executor, bool authorized) external;

    /**
     * @notice Returns whether an address is authorized to execute a given strategy.
     * @param strategyId Strategy identifier.
     * @param executor Address to check.
     * @return True if authorized.
     */
    function isAuthorizedExecutor(uint256 strategyId, address executor) external view returns (bool);

    // -------------------------------------------------------------------------
    // CONFIGURATION
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the address of the current swap executor.
     */
    function swapExecutor() external view returns (address);

    /**
     * @notice Returns the maximum age in seconds a DecisionResult remains valid.
     */
    function maxDecisionAge() external view returns (uint256);

    /**
     * @notice Updates the swap executor. Only callable by owner.
     * @param newExecutor Address of the new ISwapExecutor implementation.
     */
    function setSwapExecutor(address newExecutor) external;

    /**
     * @notice Updates the maximum accepted age of a DecisionResult. Only callable by owner.
     * @param newMaxAge New maximum age in seconds.
     */
    function setMaxDecisionAge(uint256 newMaxAge) external;
}
