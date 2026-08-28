// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketDataTypes} from "../market/MarketDataTypes.sol";
import {YieldDataTypes} from "../yield/YieldDataTypes.sol";
import {IDCAStrategy} from "./IDCAStrategy.sol";

/**
 * @title IDecisionEngine
 * @notice Interface for Module 5: Yield-Aware DCA Decision Engine.
 * @dev The DecisionEngine is a pure analytical module that consumes the outputs of
 *      Modules 1–4 and returns a deterministic DecisionResult.
 *      It does NOT execute trades, move tokens, or call Module 6.
 */
interface IDecisionEngine {
    // -------------------------------------------------------------------------
    // ENUMS & STRUCTS
    // -------------------------------------------------------------------------

    /**
     * @notice High-level action recommendation for the execution layer.
     * @custom:value EXECUTE Full or near-full execution is appropriate.
     * @custom:value PARTIAL_EXECUTION Partial execution balances market risk with DCA progress.
     * @custom:value DELAY Market and yield conditions favor waiting further.
     */
    enum DecisionAction {
        EXECUTE,
        PARTIAL_EXECUTION,
        DELAY
    }

    /**
     * @notice Configuration parameters for the DecisionEngine scoring model.
     * @dev All BPS values: 10000 = 100%.
     *      The DecisionEngine uses a deterministic configurable heuristic model.
     *      The challenge does not mandate one exact mathematical scoring formula.
     */
    struct DecisionConfig {
        // Scoring weights (must sum to 10000)
        uint256 marketWeightBps; // Weight for market score in final score
        uint256 yieldWeightBps; // Weight for yield score in final score
        uint256 strategyWeightBps; // Weight for strategy/urgency score in final score
        // Action thresholds
        uint256 executeThresholdBps; // Score >= this => EXECUTE (default 6500)
        uint256 partialThresholdBps; // Score >= this => PARTIAL_EXECUTION (default 4000)
        // Market quality thresholds (all in BPS unless noted)
        uint256 volatilityThresholdBps; // Volatility above this is unfavorable (default 3000 = 30%)
        uint256 slippageThresholdBps; // Slippage above this is unfavorable (default 200 = 2%)
        uint256 priceImpactThresholdBps; // Price impact above this is unfavorable (default 100 = 1%)
        uint256 liquidityThreshold; // Minimum acceptable liquidity in token units
        // Partial execution sizing
        uint256 partialExecutionBps; // Fraction of target to execute when partial (default 5000 = 50%)
        uint256 minimumPartialExecutionBps; // Minimum partial fraction vs max allowed (default 1000 = 10%)
        // Delay
        uint256 recommendedDelaySeconds; // Recommended delay period when DELAY is returned
    }

    /**
     * @notice Context about previous execution state passed to the engine.
     * @param lastExecutionTimestamp Unix timestamp of the last execution (0 if never executed).
     * @param lastExecutionAmount Amount executed on the last execution (0 if never).
     * @param totalExecutedSoFar Cumulative amount executed against the strategy's target allocation.
     */
    struct ExecutionContext {
        uint256 lastExecutionTimestamp;
        uint256 lastExecutionAmount;
        uint256 totalExecutedSoFar;
    }

    /**
     * @notice Structured diagnostic breakdown attached to every DecisionResult.
     * @dev Provides full transparency into each factor's contribution to the decision.
     */
    struct DecisionDiagnostics {
        // Market factors (raw values from MarketState)
        uint256 price; // 1e18 fixed point
        uint256 twap; // 1e18 fixed point
        int256 priceDeviation; // 1e18 fixed point, signed
        uint256 volatility; // 1e18 (1e18 = 100%)
        uint256 liquidity; // token units
        uint256 slippage; // BPS
        uint256 priceImpact; // BPS
        // Yield factors (from YieldAnalysis)
        uint256 currentAPY; // BPS
        uint256 estimatedWaitingYield; // asset units
        uint256 opportunityCost; // asset units
        int256 waitingBenefit; // signed, asset units
        // Scores (0–10000 BPS)
        uint256 marketScore;
        uint256 yieldScore;
        uint256 strategyScore;
        // Constraint checks
        bool minimumExecutionSatisfied;
        bool maximumExecutionSatisfied;
        bool remainingAllocationSatisfied;
        bool capitalAvailable;
        bool delayAllowed;
        bool strategyActive;
    }

    /**
     * @notice The primary output of the DecisionEngine.
     * @param action The recommended high-level action: EXECUTE, PARTIAL_EXECUTION, or DELAY.
     * @param targetAmount The strategy's full target allocation for this cycle.
     * @param executionAmount The exact recommended execution amount (0 for DELAY).
     * @param remainingAmount Remaining allocation after this execution.
     * @param recommendedDelay Recommended seconds to wait before next evaluation (0 for EXECUTE).
     * @param score Final composite decision score in BPS (0–10000, higher is more favorable).
     * @param reason Human-readable explanation generated deterministically from the decision factors.
     * @param timestamp Block timestamp at which the decision was produced.
     * @param diagnostics Detailed breakdown of each decision factor.
     */
    struct DecisionResult {
        DecisionAction action;
        uint256 targetAmount;
        uint256 executionAmount;
        uint256 remainingAmount;
        uint256 recommendedDelay;
        uint256 score;
        string reason;
        uint256 timestamp;
        DecisionDiagnostics diagnostics;
    }

    // -------------------------------------------------------------------------
    // EVALUATION FUNCTION
    // -------------------------------------------------------------------------

    /**
     * @notice Evaluates all input factors and returns a deterministic decision recommendation.
     * @dev This function is view-only. It does NOT execute trades, modify state, or call Module 6.
     * @param strategy The full DCA strategy struct from Module 1.
     * @param marketState The normalized market state from Module 3's MarketAnalyzer.
     * @param yieldAnalysis The waiting-opportunity analysis from Module 4's YieldAnalyzer.
     * @param availableCapital Underlying asset units currently available for execution in the vault.
     * @param currentDelay Seconds elapsed since the strategy's nextExecutionTime.
     * @param execContext Previous execution state.
     * @return result The complete deterministic decision result.
     */
    function evaluate(
        IDCAStrategy.Strategy calldata strategy,
        MarketDataTypes.MarketState calldata marketState,
        YieldDataTypes.YieldAnalysis calldata yieldAnalysis,
        uint256 availableCapital,
        uint256 currentDelay,
        ExecutionContext calldata execContext
    ) external view returns (DecisionResult memory result);

    /**
     * @notice Returns the current DecisionConfig.
     */
    function getConfig() external view returns (DecisionConfig memory);

    /**
     * @notice Updates the DecisionConfig. Only callable by owner.
     */
    function setConfig(DecisionConfig calldata newConfig) external;
}
