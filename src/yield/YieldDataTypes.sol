// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title YieldDataTypes
 * @notice Data structures used by Module 4: Yield Analysis
 */
library YieldDataTypes {
    /**
     * @notice A normalized representation of current yield metrics for a specific principal amount or user.
     * @param currentAPY Current simulated APY in basis points (e.g. 500 = 5.00%).
     * @param principalAssets The underlying asset balance used for these projections.
     * @param projectedYield7D Estimated yield over the next 7 days, in underlying asset units.
     * @param projectedYield30D Estimated yield over the next 30 days, in underlying asset units.
     * @param projectedYield365D Estimated yield over a full year (365 days), in underlying asset units.
     */
    struct YieldState {
        uint256 currentAPY;
        uint256 principalAssets;
        uint256 projectedYield7D;
        uint256 projectedYield30D;
        uint256 projectedYield365D;
    }
    /**
     * @notice Analytical recommendation signal for the Decision Engine.
     */
    enum Recommendation {
        WAIT,
        EXECUTE,
        NEUTRAL
    }

    /**
     * @notice Configuration assumptions for modeling waiting opportunity.
     * @param waitingPeriod Assumed time in seconds to wait before execution.
     * @param volatilityWeightBps Weighting for volatility in BPS (10000 = 100%).
     * @param deviationWeightBps Weighting for price deviation in BPS (10000 = 100%).
     * @param urgencyThresholdBps Urgency threshold in BPS that triggers EXECUTE signal.
     */
    struct AnalyzerConfig {
        uint256 waitingPeriod;
        uint256 volatilityWeightBps;
        uint256 deviationWeightBps;
        uint256 urgencyThresholdBps;
    }

    /**
     * @notice Complete yield and opportunity cost analysis for a given capital amount.
     * @param currentAPY Current APY from the yield vault in BPS.
     * @param estimatedWaitingYield Modeled yield if capital waits the configured waitingPeriod.
     * @param opportunityCost Modeled economic risk based on weighted market volatility and price deviation.
     * @param waitingBenefit Net economic benefit (estimatedWaitingYield - opportunityCost).
     * @param urgency Scaled metric (up to 10000) representing delay vs max allowed delay.
     * @param remainingDelay Seconds remaining in the execution window (0 if overdue).
     * @param recommendation Deterministic signal: WAIT, EXECUTE, or NEUTRAL.
     */
    struct YieldAnalysis {
        uint256 currentAPY;
        uint256 estimatedWaitingYield;
        uint256 opportunityCost;
        int256 waitingBenefit;
        uint256 urgency;
        uint256 remainingDelay;
        Recommendation recommendation;
    }
}
