// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IExecutionManager} from "../interfaces/IExecutionManager.sol";
import {IDecisionEngine} from "../interfaces/IDecisionEngine.sol";
import {IDCAStrategy} from "../interfaces/IDCAStrategy.sol";
import {IYieldVault} from "../interfaces/IYieldVault.sol";
import {ISwapExecutor} from "../interfaces/ISwapExecutor.sol";

/**
 * @title ExecutionManager
 * @notice Module 6 + Module 8: Execution orchestration and atomic capital withdrawal/swap execution.
 * @dev Orchestrates the execution of decisions produced by Module 5 (DecisionEngine).
 *
 *      Architecture:
 *          DecisionEngine (Module 5) → DecisionResult
 *                     │
 *                     ▼
 *          ExecutionManager (Module 6 / Module 8)
 *                     │
 *          ┌──────────┼───────────┐
 *          │          │           │
 *      Validate   YieldVault   SwapExecutor
 *                 (withdraw)   (execute swap)
 *          │          │           │
 *          └──────────┼──────────┘
 *                     │
 *                Accounting
 *
 *      MODULE 8 — ATOMIC EXECUTION GUARANTEE:
 *
 *      All state transitions within executeDecision() execute inside a SINGLE EVM transaction.
 *      If any required operation reverts, the EVM automatically rolls back:
 *        - vault shares burned / assets transferred
 *        - token allowances granted to the swap executor
 *        - execution accounting (totalExecuted, nonce, count, timestamp)
 *
 *      This provides the following atomicity guarantee:
 *        SUCCESS:  all state changes persist.
 *        FAILURE:  no state changes persist. The vault, accounting, and
 *                  token balances return to their pre-transaction state.
 *
 *      EXECUTION ORDER (Module 8 canonical sequence):
 *        1. Validate strategy exists and is ACTIVE.
 *        2. Validate caller is authorized.
 *        3. Validate nonce (replay protection).
 *        4. Validate decision freshness (stale-decision guard).
 *        5. Validate execution amount (zero / min / max / remaining).
 *        6. Validate vault liquidity.
 *        7. Withdraw ONLY the exact required amount from YieldVault.
 *        8. Execute swap via ISwapExecutor.
 *        9. Verify swap succeeded (explicit failure gate).
 *       10. Update accounting (only after confirmed swap success).
 *
 *      Steps 1–6 are pure view validations with NO capital movement.
 *      Steps 7–10 are the atomic capital movement section.
 *      If step 8 or 9 reverts, step 7 (vault withdrawal) is also rolled back.
 *
 *      WHAT THIS DOES NOT GUARANTEE:
 *        - Off-chain backend, frontend, or RPC operations are NOT covered.
 *        - Oracle/market analysis decisions are NOT atomic with execution.
 *        - Blockchain atomicity applies only to EVM state changes within
 *          the same transaction.
 *
 * @custom:security ReentrancyGuard protects the execution path.
 */
contract ExecutionManager is IExecutionManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    /// @notice Default maximum accepted age of a DecisionResult (5 minutes).
    uint256 public constant DEFAULT_MAX_DECISION_AGE = 300;

    // -------------------------------------------------------------------------
    // IMMUTABLE REFERENCES
    // -------------------------------------------------------------------------

    /// @notice Reference to Module 1: DCA Strategy Engine.
    IDCAStrategy public immutable dcaEngine;

    /// @notice Reference to Module 2: ERC-4626 Yield Vault.
    IYieldVault public immutable yieldVault;

    // -------------------------------------------------------------------------
    // MUTABLE STATE
    // -------------------------------------------------------------------------

    /// @notice Current swap executor implementation.
    ISwapExecutor private _swapExecutor;

    /// @notice Maximum accepted age (seconds) for a DecisionResult before it is stale.
    uint256 private _maxDecisionAge;

    /// @notice Per-strategy execution accounting: strategyId => ExecutionRecord.
    mapping(uint256 => ExecutionRecord) private _records;

    /// @notice Per-strategy per-executor authorization: strategyId => executor => authorized.
    mapping(uint256 => mapping(address => bool)) private _authorizedExecutors;

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    /**
     * @notice Initializes the ExecutionManager.
     * @param initialOwner Address of the administrative owner.
     * @param dcaEngine_ Address of the DCAEngine (Module 1).
     * @param yieldVault_ Address of the YieldVault (Module 2).
     * @param swapExecutor_ Address of the initial ISwapExecutor implementation.
     */
    constructor(address initialOwner, address dcaEngine_, address yieldVault_, address swapExecutor_)
        Ownable(initialOwner)
    {
        if (dcaEngine_ == address(0)) revert ZeroAddress();
        if (yieldVault_ == address(0)) revert ZeroAddress();
        if (swapExecutor_ == address(0)) revert ZeroAddress();

        dcaEngine = IDCAStrategy(dcaEngine_);
        yieldVault = IYieldVault(yieldVault_);
        _swapExecutor = ISwapExecutor(swapExecutor_);
        _maxDecisionAge = DEFAULT_MAX_DECISION_AGE;
    }

    // -------------------------------------------------------------------------
    // CONFIGURATION
    // -------------------------------------------------------------------------

    /// @inheritdoc IExecutionManager
    function swapExecutor() external view returns (address) {
        return address(_swapExecutor);
    }

    /// @inheritdoc IExecutionManager
    function maxDecisionAge() external view returns (uint256) {
        return _maxDecisionAge;
    }

    /// @inheritdoc IExecutionManager
    function setSwapExecutor(address newExecutor) external onlyOwner {
        if (newExecutor == address(0)) revert ZeroAddress();
        address old = address(_swapExecutor);
        _swapExecutor = ISwapExecutor(newExecutor);
        emit SwapExecutorUpdated(old, newExecutor);
    }

    /// @inheritdoc IExecutionManager
    function setMaxDecisionAge(uint256 newMaxAge) external onlyOwner {
        _maxDecisionAge = newMaxAge;
    }

    // -------------------------------------------------------------------------
    // AUTHORIZATION MANAGEMENT
    // -------------------------------------------------------------------------

    /// @inheritdoc IExecutionManager
    function setStrategyExecutor(uint256 strategyId, address executor, bool authorized) external {
        IDCAStrategy.Strategy memory strategy = dcaEngine.getStrategy(strategyId);
        if (msg.sender != strategy.owner) {
            revert UnauthorizedExecutor(strategyId, msg.sender);
        }
        if (executor == address(0)) revert ZeroAddress();
        _authorizedExecutors[strategyId][executor] = authorized;
    }

    /// @inheritdoc IExecutionManager
    function isAuthorizedExecutor(uint256 strategyId, address executor) external view returns (bool) {
        IDCAStrategy.Strategy memory strategy = dcaEngine.getStrategy(strategyId);
        return executor == strategy.owner || _authorizedExecutors[strategyId][executor];
    }

    // -------------------------------------------------------------------------
    // ACCOUNTING QUERIES
    // -------------------------------------------------------------------------

    /// @inheritdoc IExecutionManager
    function getExecutionRecord(uint256 strategyId) external view returns (ExecutionRecord memory record) {
        return _records[strategyId];
    }

    /// @inheritdoc IExecutionManager
    function getRemainingAllocation(uint256 strategyId) external view returns (uint256 remaining) {
        IDCAStrategy.Strategy memory strategy = dcaEngine.getStrategy(strategyId);
        ExecutionRecord storage record = _records[strategyId];
        if (record.totalExecuted >= strategy.targetAllocation) return 0;
        return strategy.targetAllocation - record.totalExecuted;
    }

    /// @inheritdoc IExecutionManager
    function getExecutionNonce(uint256 strategyId) external view returns (uint256 nonce) {
        return _records[strategyId].nonce;
    }

    // -------------------------------------------------------------------------
    // MODULE 8: PRE-FLIGHT VALIDATION (VIEW ONLY — NO CAPITAL MOVEMENT)
    // -------------------------------------------------------------------------

    /// @inheritdoc IExecutionManager
    function validateExecution(
        uint256 strategyId,
        IDecisionEngine.DecisionResult calldata decision,
        uint256 expectedNonce
    ) external view returns (uint256 validatedAmount, uint256 remainingAfter) {
        // 1. Strategy must exist and be ACTIVE
        IDCAStrategy.Strategy memory strategy = _loadAndValidateStrategy(strategyId);

        // 2. Caller must be authorized
        _validateAuthorization(strategyId, strategy);

        // 3. Nonce must match
        ExecutionRecord storage record = _records[strategyId];
        if (expectedNonce != record.nonce) {
            revert InvalidNonce(strategyId, expectedNonce, record.nonce);
        }

        // 4. Decision must not be stale
        _validateDecisionFreshness(decision);

        // 5 & 6: Only validate execution-path decisions
        if (
            decision.action == IDecisionEngine.DecisionAction.EXECUTE
                || decision.action == IDecisionEngine.DecisionAction.PARTIAL_EXECUTION
        ) {
            uint256 remaining = _computeRemainingAllocation(strategy, record);
            _validateExecutionAmount(strategyId, decision.executionAmount, strategy, remaining);

            if (strategy.inputToken != address(yieldVault.asset())) {
                revert InvalidInputToken();
            }

            // 6. Vault liquidity check
            uint256 vaultAssets = IERC20(yieldVault.asset()).balanceOf(address(yieldVault));
            if (decision.executionAmount > vaultAssets) {
                revert InsufficientVaultFunds(strategyId, decision.executionAmount, vaultAssets);
            }

            validatedAmount = decision.executionAmount;
            remainingAfter = remaining - decision.executionAmount;
        } else if (decision.action == IDecisionEngine.DecisionAction.DELAY) {
            // DELAY: valid action, no capital movement required
            validatedAmount = 0;
            remainingAfter = _computeRemainingAllocation(strategy, record);
        } else {
            revert InvalidDecisionAction();
        }
    }

    // -------------------------------------------------------------------------
    // CORE EXECUTION
    // -------------------------------------------------------------------------

    /// @inheritdoc IExecutionManager
    function executeDecision(
        uint256 strategyId,
        IDecisionEngine.DecisionResult calldata decision,
        uint256 expectedNonce,
        uint256 minSwapOutput
    ) external nonReentrant returns (ExecutionResult memory result) {
        // --- 1. Load authoritative on-chain strategy state ---
        IDCAStrategy.Strategy memory strategy = _loadAndValidateStrategy(strategyId);

        // --- 2. Validate caller authorization ---
        _validateAuthorization(strategyId, strategy);

        // --- 3. Validate nonce (replay protection) ---
        ExecutionRecord storage record = _records[strategyId];
        if (expectedNonce != record.nonce) {
            revert InvalidNonce(strategyId, expectedNonce, record.nonce);
        }

        // --- 4. Validate decision freshness ---
        _validateDecisionFreshness(decision);

        // --- 5. Emit request event ---
        emit ExecutionRequested(strategyId, msg.sender, decision.action, decision.executionAmount, record.nonce);

        // --- 6. Handle action ---
        if (decision.action == IDecisionEngine.DecisionAction.DELAY) {
            result = _handleDelay(strategyId, strategy, record, decision);
        } else if (
            decision.action == IDecisionEngine.DecisionAction.EXECUTE
                || decision.action == IDecisionEngine.DecisionAction.PARTIAL_EXECUTION
        ) {
            result = _handleExecution(strategyId, strategy, record, decision, minSwapOutput);
        } else {
            revert InvalidDecisionAction();
        }

        return result;
    }

    // -------------------------------------------------------------------------
    // INTERNAL: STRATEGY VALIDATION
    // -------------------------------------------------------------------------

    /**
     * @dev Loads the strategy from DCAEngine and validates it exists and is ACTIVE.
     */
    function _loadAndValidateStrategy(uint256 strategyId)
        internal
        view
        returns (IDCAStrategy.Strategy memory strategy)
    {
        // getStrategy reverts with StrategyNotFound if non-existent
        strategy = dcaEngine.getStrategy(strategyId);

        if (strategy.status != IDCAStrategy.StrategyStatus.ACTIVE) {
            revert StrategyNotActive(strategyId);
        }
    }

    /**
     * @dev Validates that msg.sender is the strategy owner or an authorized executor.
     */
    function _validateAuthorization(uint256 strategyId, IDCAStrategy.Strategy memory strategy) internal view {
        if (msg.sender != strategy.owner && !_authorizedExecutors[strategyId][msg.sender]) {
            revert UnauthorizedExecutor(strategyId, msg.sender);
        }
    }

    /**
     * @dev Validates that the decision is not stale.
     */
    function _validateDecisionFreshness(IDecisionEngine.DecisionResult calldata decision) internal view {
        if (_maxDecisionAge > 0 && block.timestamp > decision.timestamp + _maxDecisionAge) {
            revert StaleDecision(decision.timestamp, block.timestamp, _maxDecisionAge);
        }
    }

    // -------------------------------------------------------------------------
    // INTERNAL: DELAY HANDLING
    // -------------------------------------------------------------------------

    /**
     * @dev Processes a DELAY action: no capital movement, advance nonce, emit event.
     */
    function _handleDelay(
        uint256 strategyId,
        IDCAStrategy.Strategy memory strategy,
        ExecutionRecord storage record,
        IDecisionEngine.DecisionResult calldata decision
    ) internal returns (ExecutionResult memory result) {
        uint256 currentNonce = record.nonce;
        record.nonce = currentNonce + 1;

        uint256 remaining = _computeRemainingAllocation(strategy, record);

        result = ExecutionResult({
            strategyId: strategyId,
            status: ExecutionStatus.DELAYED,
            action: decision.action,
            requestedAmount: 0,
            executedAmount: 0,
            withdrawnAmount: 0,
            swapOutputAmount: 0,
            remainingAllocation: remaining,
            timestamp: block.timestamp,
            nonce: currentNonce
        });

        emit ExecutionDelayed(strategyId, decision.recommendedDelay, currentNonce);
    }

    // -------------------------------------------------------------------------
    // INTERNAL: EXECUTION HANDLING
    // -------------------------------------------------------------------------

    /**
     * @dev Processes an EXECUTE or PARTIAL_EXECUTION action.
     *
     *      MODULE 8 — ATOMIC EXECUTION SEQUENCE:
     *
     *      All of the following occur within a single EVM call frame.
     *      Any revert at any step rolls back all preceding state changes.
     *
     *      VALIDATION (no capital movement):
     *        a. Execution amount ≥ minExecutionAmount
     *        b. Execution amount ≤ maxExecutionAmount
     *        c. Execution amount ≤ remaining allocation
     *        d. Vault holds sufficient underlying assets
     *
     *      CAPITAL MOVEMENT (atomic boundary below):
     *        e. withdrawForStrategy: burns shares, transfers assets to this contract
     *        f. executeSwap: swap executor consumes input, delivers output to receiver
     *        g. Verify swapResult.success (explicit failure gate)
     *
     *      ACCOUNTING (only written after confirmed swap success):
     *        h. totalExecuted += inputConsumed
     *        i. lastExecutionTimestamp, lastExecutionAmount, executionCount, nonce
     *
     *      If step (f) or (g) reverts, step (e) is rolled back by the EVM.
     *      Accounting (h, i) is never written on a reverted transaction.
     */
    function _handleExecution(
        uint256 strategyId,
        IDCAStrategy.Strategy memory strategy,
        ExecutionRecord storage record,
        IDecisionEngine.DecisionResult calldata decision,
        uint256 minSwapOutput
    ) internal returns (ExecutionResult memory result) {
        uint256 currentNonce = record.nonce;
        uint256 requestedAmount = decision.executionAmount;

        // --- Validate execution amount against on-chain constraints ---
        uint256 remaining = _computeRemainingAllocation(strategy, record);
        _validateExecutionAmount(strategyId, requestedAmount, strategy, remaining);

        // --- Validate input token matches vault asset ---
        if (strategy.inputToken != address(yieldVault.asset())) {
            revert InvalidInputToken();
        }

        // --- Validate vault liquidity ---
        uint256 vaultAssets = IERC20(yieldVault.asset()).balanceOf(address(yieldVault));
        if (requestedAmount > vaultAssets) {
            revert InsufficientVaultFunds(strategyId, requestedAmount, vaultAssets);
        }

        emit ExecutionValidated(strategyId, requestedAmount, currentNonce);

        // --- Withdraw capital from YieldVault ---
        uint256 sharesBurned = yieldVault.withdrawForStrategy(strategy.owner, requestedAmount, address(this));

        emit CapitalWithdrawn(strategyId, strategy.owner, requestedAmount, sharesBurned);

        // --- Approve and execute swap ---
        IERC20(strategy.inputToken).safeIncreaseAllowance(address(_swapExecutor), requestedAmount);

        ISwapExecutor.SwapParams memory swapParams = ISwapExecutor.SwapParams({
            strategyId: strategyId,
            user: strategy.owner,
            inputToken: strategy.inputToken,
            targetToken: strategy.targetToken,
            inputAmount: requestedAmount,
            minOutputAmount: minSwapOutput,
            receiver: strategy.owner
        });

        ISwapExecutor.SwapResult memory swapResult = _swapExecutor.executeSwap(swapParams);

        if (!swapResult.success) {
            revert SwapExecutionFailed(strategyId, requestedAmount);
        }

        emit SwapExecuted(strategyId, swapResult.inputConsumed, swapResult.outputReceived);

        // --- Update accounting ---
        record.totalExecuted += swapResult.inputConsumed;
        record.lastExecutionTimestamp = block.timestamp;
        record.lastExecutionAmount = swapResult.inputConsumed;
        record.executionCount += 1;
        record.nonce = currentNonce + 1;

        uint256 newRemaining = _computeRemainingAllocation(strategy, record);

        result = ExecutionResult({
            strategyId: strategyId,
            status: ExecutionStatus.SUCCESS,
            action: decision.action,
            requestedAmount: requestedAmount,
            executedAmount: swapResult.inputConsumed,
            withdrawnAmount: requestedAmount,
            swapOutputAmount: swapResult.outputReceived,
            remainingAllocation: newRemaining,
            timestamp: block.timestamp,
            nonce: currentNonce
        });

        emit ExecutionCompleted(
            strategyId,
            strategy.owner,
            swapResult.inputConsumed,
            swapResult.outputReceived,
            newRemaining,
            currentNonce,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // INTERNAL: AMOUNT VALIDATION
    // -------------------------------------------------------------------------

    /**
     * @dev Validates the execution amount against the strategy's hard constraints and remaining allocation.
     */
    function _validateExecutionAmount(
        uint256 strategyId,
        uint256 amount,
        IDCAStrategy.Strategy memory strategy,
        uint256 remaining
    ) internal pure {
        if (amount == 0) {
            revert ZeroExecutionAmount(strategyId);
        }

        if (amount < strategy.minExecutionAmount) {
            revert BelowMinimumExecution(strategyId, amount, strategy.minExecutionAmount);
        }

        if (amount > strategy.maxExecutionAmount) {
            revert AboveMaximumExecution(strategyId, amount, strategy.maxExecutionAmount);
        }

        if (amount > remaining) {
            revert ExceedsRemainingAllocation(strategyId, amount, remaining);
        }
    }

    // -------------------------------------------------------------------------
    // INTERNAL: HELPERS
    // -------------------------------------------------------------------------

    /**
     * @dev Computes remaining allocation: targetAllocation - totalExecuted.
     */
    function _computeRemainingAllocation(IDCAStrategy.Strategy memory strategy, ExecutionRecord storage record)
        internal
        view
        returns (uint256)
    {
        if (record.totalExecuted >= strategy.targetAllocation) return 0;
        return strategy.targetAllocation - record.totalExecuted;
    }
}
