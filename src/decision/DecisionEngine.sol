// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDecisionEngine} from "../interfaces/IDecisionEngine.sol";
import {IDCAStrategy} from "../interfaces/IDCAStrategy.sol";
import {MarketDataTypes} from "../market/MarketDataTypes.sol";
import {YieldDataTypes} from "../yield/YieldDataTypes.sol";

/**
 * @title DecisionEngine
 * @notice Module 5: Yield-Aware DCA Decision Engine.
 * @dev A purely analytical, view-only module that evaluates market conditions, yield
 *      opportunity, and strategy constraints to produce a deterministic DecisionResult.
 *
 *      Architecture:
 *
 *          DCAEngine (Module 1)
 *               │ Strategy
 *          MarketAnalyzer (Module 3) → MarketState
 *          YieldAnalyzer (Module 4)  → YieldAnalysis
 *               │
 *               ▼
 *         DecisionEngine (Module 5)
 *               │
 *               ▼
 *         DecisionResult
 *               │
 *               ▼
 *         Future ExecutionManager (Module 6)
 *
 *      IMPORTANT: This module produces a decision recommendation ONLY.
 *      It does NOT execute swaps, withdraw tokens, or call Module 6.
 *
 *      SCORING MODEL (all in BPS, 10000 = 100%):
 *
 *      The DecisionEngine uses a deterministic configurable heuristic model.
 *      The challenge does not mandate one exact mathematical scoring formula.
 *      Weights and thresholds are configurable.
 *
 *      MARKET SCORE: evaluates price deviation, volatility, liquidity, slippage, price impact.
 *      YIELD SCORE: evaluates APY attractiveness and waiting benefit vs. opportunity cost.
 *      STRATEGY SCORE: evaluates urgency (delay elapsed / max delay) and execution constraints.
 *
 *      Final score = (marketScore * marketWeight + yieldScore * yieldWeight + strategyScore * strategyWeight) / 10000
 *
 *      scale: all scores are 0–10000 BPS.
 *
 *      UNITS:
 *      - volatility: 1e18 = 100% (from MarketDataTypes)
 *      - priceDeviation: 1e18 fixed-point, signed (from MarketDataTypes)
 *      - slippage / priceImpact: BPS (from MarketDataTypes)
 *      - APY: BPS (from YieldDataTypes)
 *      - waitingBenefit / opportunityCost: underlying asset units (from YieldDataTypes)
 *      - urgency: BPS, 0–10000 (from YieldDataTypes)
 *
 * @dev No ML, AI, LLMs, randomness, or off-chain dependencies are used.
 *      No Uniswap or swap execution is implemented.
 */
contract DecisionEngine is IDecisionEngine, Ownable {
    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------

    error InvalidConfig();
    error InvalidWeightsSum(uint256 sum);

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    uint256 private constant BPS = 10_000;
    uint256 private constant ONE_E18 = 1e18;

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------

    DecisionConfig private _config;

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    /**
     * @param initialOwner Owner address for configuration management.
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        // Sensible deterministic defaults
        _config = DecisionConfig({
            marketWeightBps: 3500, // 35%
            yieldWeightBps: 2500, // 25%
            strategyWeightBps: 4000, // 40%
            executeThresholdBps: 6500, // Score >= 65% => EXECUTE
            partialThresholdBps: 4000, // Score >= 40% => PARTIAL_EXECUTION
            volatilityThresholdBps: 3000, // 30% volatility threshold (1e18 scale normalized to BPS)
            slippageThresholdBps: 200, // 2% slippage threshold
            priceImpactThresholdBps: 100, // 1% price impact threshold
            liquidityThreshold: 1e18, // 1 token unit minimum liquidity
            partialExecutionBps: 5000, // Execute 50% of target when partial
            minimumPartialExecutionBps: 1000, // Minimum 10% of maxExecution for partial
            recommendedDelaySeconds: 3600 // 1 hour recommended delay
        });
    }

    // -------------------------------------------------------------------------
    // CONFIGURATION
    // -------------------------------------------------------------------------

    /// @inheritdoc IDecisionEngine
    function getConfig() external view returns (DecisionConfig memory) {
        return _config;
    }

    /// @inheritdoc IDecisionEngine
    function setConfig(DecisionConfig calldata newConfig) external onlyOwner {
        _validateConfig(newConfig);
        _config = newConfig;
    }

    // -------------------------------------------------------------------------
    // MAIN EVALUATION
    // -------------------------------------------------------------------------

    struct EvaluateLocals {
        bool strategyActive;
        bool delayAllowed;
        uint256 remainingAllocation;
        uint256 executionCap;
        uint256 marketScore;
        uint256 yieldScore;
        uint256 strategyScore;
        uint256 finalScore;
        bool maxDelayReached;
    }

    /// @inheritdoc IDecisionEngine
    function evaluate(
        IDCAStrategy.Strategy calldata strategy,
        MarketDataTypes.MarketState calldata marketState,
        YieldDataTypes.YieldAnalysis calldata yieldAnalysis,
        uint256 availableCapital,
        uint256 currentDelay,
        ExecutionContext calldata execContext
    ) external view returns (DecisionResult memory result) {
        DecisionConfig memory cfg = _config;
        result.timestamp = block.timestamp;
        EvaluateLocals memory vars;

        // 1. Validate strategy is eligible
        vars.strategyActive = _isStrategyActive(strategy);
        vars.delayAllowed = currentDelay < strategy.maxDelay;

        // 2. Determine available execution headroom
        vars.remainingAllocation = _remainingAllocation(strategy, execContext);
        vars.executionCap = _executionCap(strategy, availableCapital, vars.remainingAllocation);

        // 3. Build diagnostics
        result.diagnostics = _buildDiagnostics(
            marketState,
            yieldAnalysis,
            strategy,
            availableCapital,
            vars.remainingAllocation,
            vars.executionCap,
            vars.strategyActive,
            vars.delayAllowed
        );

        result.targetAmount = strategy.targetAllocation;

        // 4. Short-circuit: strategy not executable
        if (!vars.strategyActive || vars.remainingAllocation == 0) {
            result.action = DecisionAction.DELAY;
            result.executionAmount = 0;
            result.remainingAmount = vars.remainingAllocation;
            result.recommendedDelay = strategy.maxDelay;
            result.score = 0;
            result.reason = !vars.strategyActive
                ? "Strategy is not in an ACTIVE state. No execution is possible."
                : "Remaining allocation is zero. Strategy target has been fully met.";
            return result;
        }

        // 5. Compute component scores
        vars.marketScore = _computeMarketScore(marketState, cfg);
        vars.yieldScore = _computeYieldScore(yieldAnalysis);
        vars.strategyScore = _computeStrategyScore(yieldAnalysis.urgency, strategy, vars.executionCap);

        result.diagnostics.marketScore = vars.marketScore;
        result.diagnostics.yieldScore = vars.yieldScore;
        result.diagnostics.strategyScore = vars.strategyScore;

        // 6. Final weighted score
        vars.finalScore =
            (vars.marketScore
                    * cfg.marketWeightBps
                    + vars.yieldScore
                    * cfg.yieldWeightBps
                    + vars.strategyScore
                    * cfg.strategyWeightBps) / BPS;
        result.score = vars.finalScore;

        // 7. Maximum-delay override: must not DELAY when window is exhausted
        vars.maxDelayReached = currentDelay >= strategy.maxDelay;

        // 8. Determine action
        (result.action, result.executionAmount, result.recommendedDelay, result.reason) = _determineAction(
            ActionContext({
                finalScore: vars.finalScore,
                yieldAnalysis: yieldAnalysis,
                strategy: strategy,
                availableCapital: availableCapital,
                remainingAllocation: vars.remainingAllocation,
                executionCap: vars.executionCap,
                currentDelay: currentDelay,
                maxDelayReached: vars.maxDelayReached,
                delayAllowed: vars.delayAllowed,
                cfg: cfg
            })
        );

        result.remainingAmount =
            vars.remainingAllocation > result.executionAmount ? vars.remainingAllocation - result.executionAmount : 0;
    }

    // -------------------------------------------------------------------------
    // INTERNAL: SCORING
    // -------------------------------------------------------------------------

    /**
     * @notice Computes a market quality score (0–10000 BPS).
     * @dev High score = favorable market conditions.
     *
     *      Factors:
     *      1. priceDeviation: negative deviation (price < TWAP) is favorable (buying below average).
     *         Score contribution starts at 5000 (neutral) and shifts based on deviation magnitude.
     *      2. volatility: low volatility is favorable. Above threshold penalizes score.
     *      3. slippage: low slippage is favorable. Above threshold penalizes score.
     *      4. priceImpact: low impact is favorable. Above threshold penalizes score.
     *      5. liquidity: above threshold is favorable.
     *
     *      Each factor contributes equally (20% weight of the 10000 BPS total).
     *
     *      SCALE NOTE:
     *      - volatility from MarketDataTypes: 1e18 = 100%. Normalized to BPS: (vol * BPS) / 1e18.
     *      - priceDeviation: 1e18 scale, signed.
     *      - slippage/priceImpact: already in BPS from MarketAnalyzer.
     */
    function _computeMarketScore(MarketDataTypes.MarketState calldata market, DecisionConfig memory cfg)
        internal
        pure
        returns (uint256 score)
    {
        // Factor 1: Price deviation (favorable = negative, buying below TWAP)
        uint256 deviationScore;
        if (market.twap == 0) {
            deviationScore = 5000; // neutral
        } else {
            // priceDeviation = currentPrice - twap (1e18 scale)
            // Negative means price < twap (favorable for buyers)
            if (market.priceDeviation <= 0) {
                // How far below TWAP in BPS?
                uint256 absDev = uint256(-market.priceDeviation);
                uint256 devBps = (absDev * BPS) / market.twap;
                // Cap improvement at 5000 BPS above neutral
                uint256 improvement = devBps > 5000 ? 5000 : devBps;
                deviationScore = 5000 + improvement;
            } else {
                // Price above TWAP — unfavorable for buyers
                uint256 devBps = (uint256(market.priceDeviation) * BPS) / market.twap;
                uint256 penalty = devBps > 5000 ? 5000 : devBps;
                deviationScore = 5000 > penalty ? 5000 - penalty : 0;
            }
        }

        // Factor 2: Volatility (low = favorable)
        // volatility is 1e18 scale; normalize to BPS first
        uint256 volBps = (market.volatility * BPS) / ONE_E18;
        uint256 volatilityScore;
        if (volBps <= cfg.volatilityThresholdBps) {
            // Below threshold: fully favorable
            volatilityScore = BPS;
        } else {
            // Linearly degrade: at 2× threshold => score 0
            uint256 excess = volBps - cfg.volatilityThresholdBps;
            volatilityScore =
                excess >= cfg.volatilityThresholdBps ? 0 : BPS - (excess * BPS) / cfg.volatilityThresholdBps;
        }

        // Factor 3: Slippage (already in BPS)
        uint256 slippageScore;
        if (market.estimatedSlippage <= cfg.slippageThresholdBps) {
            slippageScore = BPS;
        } else {
            uint256 excess = market.estimatedSlippage - cfg.slippageThresholdBps;
            slippageScore = excess >= cfg.slippageThresholdBps ? 0 : BPS - (excess * BPS) / cfg.slippageThresholdBps;
        }

        // Factor 4: Price impact (already in BPS)
        uint256 impactScore;
        if (market.estimatedPriceImpact <= cfg.priceImpactThresholdBps) {
            impactScore = BPS;
        } else {
            uint256 excess = market.estimatedPriceImpact - cfg.priceImpactThresholdBps;
            impactScore = excess >= cfg.priceImpactThresholdBps ? 0 : BPS - (excess * BPS) / cfg.priceImpactThresholdBps;
        }

        // Factor 5: Liquidity
        uint256 liquidityScore = (market.liquidity >= cfg.liquidityThreshold) ? BPS : 0;

        // Combine: equal weight (20% each => sum / 5)
        score = (deviationScore + volatilityScore + slippageScore + impactScore + liquidityScore) / 5;
    }

    /**
     * @notice Computes a yield attractiveness score (0–10000 BPS).
     * @dev WAIT recommendation from Module 4 → favorable yield → high score.
     *      EXECUTE recommendation → yield is unattractive → low score.
     *      waitingBenefit > 0 → add bonus; < 0 → add penalty.
     *      APY contribution: higher APY → better score, capped at some maximum.
     *
     *      Scale: APY in BPS (10000 = 100%). Scores normalized to 0–10000.
     */
    function _computeYieldScore(YieldDataTypes.YieldAnalysis calldata analysis) internal pure returns (uint256 score) {
        // Base score from Module 4 recommendation signal
        uint256 baseScore;
        if (analysis.recommendation == YieldDataTypes.Recommendation.WAIT) {
            baseScore = 8000; // High yield attractiveness
        } else if (analysis.recommendation == YieldDataTypes.Recommendation.NEUTRAL) {
            baseScore = 5000;
        } else {
            // Recommendation.EXECUTE: yield does not favor waiting
            baseScore = 2000;
        }

        // Adjust based on APY: APY 1000 BPS (10%) = full bonus; scale proportionally
        // Cap bonus at 1000 BPS (10% of 10000 scale)
        uint256 apyBonus = analysis.currentAPY > 1000 ? 1000 : analysis.currentAPY;

        // Waiting benefit adjustment: if benefit > 0, adds up to 1000 bonus, else subtract up to 1000
        int256 benefitAdjustment = 0;
        if (analysis.waitingBenefit > 0) {
            benefitAdjustment = 1000;
        } else if (analysis.waitingBenefit < 0) {
            benefitAdjustment = -1000;
        }

        int256 rawScore = int256(baseScore) + int256(apyBonus) + benefitAdjustment;
        if (rawScore < 0) return 0;
        score = uint256(rawScore);
        if (score > BPS) score = BPS;
    }

    /**
     * @notice Computes a strategy-urgency score (0–10000 BPS).
     * @dev High urgency (approaching max delay) → HIGH score (must execute soon).
     *      execution amount feasibility also contributes.
     *
     *      urgency from Module 4 is already 0–10000 BPS.
     *      We use it directly for the urgency contribution (70% weight).
     *      Execution feasibility (can we actually execute?) contributes the remaining 30%.
     */
    function _computeStrategyScore(uint256 urgency, IDCAStrategy.Strategy calldata strategy, uint256 executionCap)
        internal
        pure
        returns (uint256 score)
    {
        // urgency is already 0–10000 from Module 4
        uint256 urgencyScore = urgency; // 0–10000

        // Execution feasibility: can we execute at least minExecutionAmount?
        uint256 feasibilityScore = (executionCap >= strategy.minExecutionAmount) ? BPS : 0;

        // 70% urgency, 30% feasibility
        score = (urgencyScore * 7000 + feasibilityScore * 3000) / BPS;
    }

    // -------------------------------------------------------------------------
    // INTERNAL: DECISION LOGIC
    // -------------------------------------------------------------------------

    struct _DecisionVars {
        bool canExecuteMin;
        bool maxDelayReached;
        bool delayAllowed;
        uint256 remainingDelay;
    }

    struct ActionContext {
        uint256 finalScore;
        YieldDataTypes.YieldAnalysis yieldAnalysis;
        IDCAStrategy.Strategy strategy;
        uint256 availableCapital;
        uint256 remainingAllocation;
        uint256 executionCap;
        uint256 currentDelay;
        bool maxDelayReached;
        bool delayAllowed;
        DecisionConfig cfg;
    }

    function _determineAction(ActionContext memory ctx)
        internal
        pure
        returns (DecisionAction action, uint256 executionAmount, uint256 recommendedDelay, string memory reason)
    {
        _DecisionVars memory v;
        v.canExecuteMin = ctx.executionCap >= ctx.strategy.minExecutionAmount;
        v.maxDelayReached = ctx.maxDelayReached;
        v.delayAllowed = ctx.delayAllowed;
        v.remainingDelay = (ctx.strategy.maxDelay > ctx.currentDelay) ? ctx.strategy.maxDelay - ctx.currentDelay : 0;

        // MAXIMUM DELAY OVERRIDE
        if (v.maxDelayReached) {
            return _handleMaxDelayReached(v.canExecuteMin, ctx.executionCap, ctx.strategy);
        }

        // EXECUTE
        if (ctx.finalScore >= ctx.cfg.executeThresholdBps && v.canExecuteMin) {
            uint256 amount = _clampExecution(ctx.executionCap, ctx.strategy);
            return (
                DecisionAction.EXECUTE,
                amount,
                0,
                _buildExecuteReason(ctx.finalScore, ctx.yieldAnalysis, ctx.availableCapital, ctx.remainingAllocation)
            );
        }

        // PARTIAL EXECUTION
        if (ctx.finalScore >= ctx.cfg.partialThresholdBps && v.canExecuteMin) {
            uint256 partialTarget = (ctx.strategy.maxExecutionAmount * ctx.cfg.partialExecutionBps) / BPS;
            uint256 capped = partialTarget > ctx.executionCap ? ctx.executionCap : partialTarget;
            uint256 amount = _clampExecution(capped, ctx.strategy);
            if (amount >= ctx.strategy.minExecutionAmount) {
                return (
                    DecisionAction.PARTIAL_EXECUTION,
                    amount,
                    ctx.cfg.recommendedDelaySeconds,
                    _buildPartialReason(ctx.finalScore, ctx.yieldAnalysis)
                );
            }
        }

        // DELAY
        if (v.delayAllowed) {
            uint256 delay =
                v.remainingDelay < ctx.cfg.recommendedDelaySeconds ? v.remainingDelay : ctx.cfg.recommendedDelaySeconds;
            return (
                DecisionAction.DELAY,
                0,
                delay,
                _buildDelayReason(ctx.finalScore, ctx.yieldAnalysis, ctx.remainingAllocation, ctx.availableCapital)
            );
        }

        // Fallback: window closing, force execute
        if (v.canExecuteMin) {
            uint256 amount = _clampExecution(ctx.executionCap, ctx.strategy);
            return (
                DecisionAction.EXECUTE,
                amount,
                0,
                "Delay window is closing. Executing to avoid exceeding maximum allowed delay."
            );
        }

        return
            (DecisionAction.DELAY, 0, 0, "Insufficient capital and delay window closing. No valid execution possible.");
    }

    function _handleMaxDelayReached(bool canExecuteMin, uint256 executionCap, IDCAStrategy.Strategy memory strategy)
        internal
        pure
        returns (DecisionAction, uint256, uint256, string memory)
    {
        if (!canExecuteMin) {
            return (
                DecisionAction.DELAY,
                0,
                0,
                "Maximum delay reached but available capital is insufficient to meet minimum execution constraint. No valid execution is possible."
            );
        }
        uint256 amount = _clampExecution(executionCap, strategy);
        if (amount >= strategy.minExecutionAmount) {
            return (
                DecisionAction.EXECUTE,
                amount,
                0,
                "Maximum allowed delay has been reached. Further delay is prohibited. Executing the maximum valid amount permitted by strategy and capital constraints."
            );
        }
        return (
            DecisionAction.PARTIAL_EXECUTION,
            amount,
            0,
            "Maximum allowed delay reached. Partial execution selected to satisfy minimum execution constraints."
        );
    }

    // -------------------------------------------------------------------------
    // INTERNAL: AMOUNT CALCULATION
    // -------------------------------------------------------------------------

    /**
     * @notice Clamps an execution amount to be within [minExecutionAmount, maxExecutionAmount].
     */
    function _clampExecution(uint256 desiredAmount, IDCAStrategy.Strategy memory strategy)
        internal
        pure
        returns (uint256)
    {
        if (desiredAmount > strategy.maxExecutionAmount) {
            desiredAmount = strategy.maxExecutionAmount;
        }
        if (desiredAmount < strategy.minExecutionAmount) {
            return 0; // Cannot satisfy min constraint
        }
        return desiredAmount;
    }

    /**
     * @notice Returns the effective execution cap accounting for capital and remaining allocation.
     */
    function _executionCap(
        IDCAStrategy.Strategy calldata strategy,
        uint256 availableCapital,
        uint256 remainingAllocation
    ) internal pure returns (uint256 cap) {
        cap = strategy.maxExecutionAmount;
        if (availableCapital < cap) cap = availableCapital;
        if (remainingAllocation < cap) cap = remainingAllocation;
    }

    /**
     * @notice Returns remaining allocation based on execution context.
     * @dev If totalExecutedSoFar exceeds targetAllocation, returns 0.
     */
    function _remainingAllocation(IDCAStrategy.Strategy calldata strategy, ExecutionContext calldata execContext)
        internal
        pure
        returns (uint256)
    {
        if (execContext.totalExecutedSoFar >= strategy.targetAllocation) return 0;
        return strategy.targetAllocation - execContext.totalExecutedSoFar;
    }

    // -------------------------------------------------------------------------
    // INTERNAL: REASON GENERATION
    // -------------------------------------------------------------------------

    function _buildExecuteReason(
        uint256 score,
        YieldDataTypes.YieldAnalysis memory yield,
        uint256 availableCapital,
        uint256 remainingAllocation
    ) internal pure returns (string memory) {
        if (yield.waitingBenefit > 0 && score >= 8000) {
            return "Market conditions are highly favorable: price deviation is attractive, liquidity is sufficient, and price impact is low. Vault yield is also attractive but execution conditions dominate. Full DCA execution is recommended.";
        } else if (availableCapital >= remainingAllocation) {
            return "Market conditions are favorable and sufficient capital is available. Estimated slippage and price impact are within acceptable thresholds. Executing the full permitted allocation.";
        } else {
            return "Composite score meets the execution threshold. Market, yield, and strategy urgency factors collectively favor immediate DCA execution within available capital constraints.";
        }
    }

    function _buildPartialReason(uint256 score, YieldDataTypes.YieldAnalysis memory yield)
        internal
        pure
        returns (string memory)
    {
        if (yield.waitingBenefit < 0) {
            return "The modeled waiting benefit is negative (opportunity cost exceeds estimated yield). Market conditions are mixed. Partial execution maintains DCA progress while limiting exposure to current market risk.";
        } else if (score >= 5000) {
            return "Market and yield conditions are moderately favorable. High volatility or elevated price impact makes full execution inadvisable. Partial execution maintains DCA progress while reducing execution risk.";
        } else {
            return "Composite conditions score above the partial execution threshold. A partial DCA execution balances progress against current market and yield uncertainty.";
        }
    }

    function _buildDelayReason(
        uint256,
        /* score */
        YieldDataTypes.YieldAnalysis memory yield,
        uint256 remainingAllocation,
        uint256 availableCapital
    ) internal pure returns (string memory) {
        if (availableCapital < remainingAllocation && availableCapital == 0) {
            return "No capital is currently available in the vault. Delaying until capital is deposited.";
        } else if (yield.waitingBenefit > 0 && yield.recommendation == YieldDataTypes.Recommendation.WAIT) {
            return "Market conditions are unfavorable. Estimated waiting yield currently exceeds the modeled opportunity cost of waiting. Delaying execution to allow market conditions to improve.";
        } else {
            return "Composite decision score is below the execution threshold. Market conditions (volatility, slippage, or price impact) are currently unfavorable. Execution is delayed pending improved conditions.";
        }
    }

    // -------------------------------------------------------------------------
    // INTERNAL: HELPERS
    // -------------------------------------------------------------------------

    function _isStrategyActive(IDCAStrategy.Strategy calldata strategy) internal pure returns (bool) {
        return strategy.status == IDCAStrategy.StrategyStatus.ACTIVE;
    }

    function _buildDiagnostics(
        MarketDataTypes.MarketState calldata market,
        YieldDataTypes.YieldAnalysis calldata yield,
        IDCAStrategy.Strategy calldata strategy,
        uint256 availableCapital,
        uint256 remainingAllocation,
        uint256 executionCap,
        bool strategyActive,
        bool delayAllowed
    ) internal pure returns (DecisionDiagnostics memory d) {
        d.price = market.currentPrice;
        d.twap = market.twap;
        d.priceDeviation = market.priceDeviation;
        d.volatility = market.volatility;
        d.liquidity = market.liquidity;
        d.slippage = market.estimatedSlippage;
        d.priceImpact = market.estimatedPriceImpact;
        d.currentAPY = yield.currentAPY;
        d.estimatedWaitingYield = yield.estimatedWaitingYield;
        d.opportunityCost = yield.opportunityCost;
        d.waitingBenefit = yield.waitingBenefit;
        d.strategyActive = strategyActive;
        d.delayAllowed = delayAllowed;
        d.capitalAvailable = availableCapital >= strategy.minExecutionAmount;
        d.remainingAllocationSatisfied = remainingAllocation >= strategy.minExecutionAmount;
        d.minimumExecutionSatisfied = executionCap >= strategy.minExecutionAmount;
        d.maximumExecutionSatisfied = executionCap <= strategy.maxExecutionAmount;
    }

    // -------------------------------------------------------------------------
    // INTERNAL: VALIDATION
    // -------------------------------------------------------------------------

    function _validateConfig(DecisionConfig calldata cfg) internal pure {
        // Weights must sum to BPS
        uint256 weightSum = cfg.marketWeightBps + cfg.yieldWeightBps + cfg.strategyWeightBps;
        if (weightSum != BPS) revert InvalidWeightsSum(weightSum);

        // Thresholds must be within BPS range
        if (cfg.executeThresholdBps > BPS) revert InvalidConfig();
        if (cfg.partialThresholdBps > BPS) revert InvalidConfig();
        if (cfg.partialThresholdBps > cfg.executeThresholdBps) revert InvalidConfig();
        if (cfg.volatilityThresholdBps > BPS) revert InvalidConfig();
        if (cfg.slippageThresholdBps > BPS) revert InvalidConfig();
        if (cfg.priceImpactThresholdBps > BPS) revert InvalidConfig();
        if (cfg.partialExecutionBps > BPS) revert InvalidConfig();
        if (cfg.minimumPartialExecutionBps > BPS) revert InvalidConfig();
    }
}
