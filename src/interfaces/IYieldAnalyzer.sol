// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldDataTypes} from "../yield/YieldDataTypes.sol";

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
}
