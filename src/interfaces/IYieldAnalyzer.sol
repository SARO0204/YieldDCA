// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldDataTypes} from "../yield/YieldDataTypes.sol";
import {MarketDataTypes} from "../market/MarketDataTypes.sol";

/**
 * @title IYieldAnalyzer
 * @notice Interface for retrieving normalized yield analysis metrics for the Decision Engine.
 */
interface IYieldAnalyzer {
    /**
     * @notice Returns the yield state projections for a specific user's vault balance.
     * @param user The address of the vault shareholder.
     * @return A YieldState struct containing APY and projected yield amounts.
     */
    function getYieldStateForUser(address user) external view returns (YieldDataTypes.YieldState memory);

    /**
     * @notice Returns the yield state projections for an arbitrary principal asset amount.
     * @param principalAmount The theoretical underlying asset amount to analyze.
     * @return A YieldState struct containing APY and projected yield amounts.
     */
    function getYieldStateForAmount(uint256 principalAmount) external view returns (YieldDataTypes.YieldState memory);

    /**
     * @notice Performs a full deterministic waiting-opportunity analysis for the Decision Engine.
     * @param principal Capital amount available to DCA.
     * @param marketState The normalized market state provided by MarketAnalyzer.
     * @param currentDelay Seconds elapsed since the execution window opened.
     * @param maxDelay Maximum allowed seconds for the execution window.
     * @return A YieldAnalysis struct containing estimated yields, risks, and a recommendation.
     */
    function analyzeYieldOpportunity(
        uint256 principal,
        MarketDataTypes.MarketState memory marketState,
        uint256 currentDelay,
        uint256 maxDelay
    ) external view returns (YieldDataTypes.YieldAnalysis memory);
}
