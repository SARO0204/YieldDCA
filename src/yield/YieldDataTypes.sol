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
}
