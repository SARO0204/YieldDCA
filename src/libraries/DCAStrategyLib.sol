// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDCAStrategy} from "../interfaces/IDCAStrategy.sol";

/**
 * @title DCAStrategyLib
 * @notice Pure library containing validation routines and scheduling calculations for DCA strategies.
 * @dev Stateless library containing zero blockchain state, zero token transfers, and zero market logic.
 */
library DCAStrategyLib {
    /**
     * @notice Validates parameters for strategy creation and determines initial `nextExecutionTime`.
     * @param params Strategy creation parameter struct.
     * @param currentTimestamp Current block timestamp (`block.timestamp`).
     * @return nextExecutionTime Resolved initial nextExecutionTime (defaults to `currentTimestamp` if 0).
     */
    function validateStrategyParams(IDCAStrategy.StrategyParams memory params, uint256 currentTimestamp)
        internal
        pure
        returns (uint256 nextExecutionTime)
    {
        if (params.inputToken == address(0)) revert IDCAStrategy.ZeroAddressInputToken();
        if (params.targetToken == address(0)) revert IDCAStrategy.ZeroAddressTargetToken();
        if (params.inputToken == params.targetToken) revert IDCAStrategy.IdenticalTokens(params.inputToken);

        validateUpdateParams(
            params.targetAllocation,
            params.frequency,
            params.maxDelay,
            params.minExecutionAmount,
            params.maxExecutionAmount
        );

        if (params.firstExecutionTime == 0) {
            nextExecutionTime = currentTimestamp;
        } else {
            if (params.firstExecutionTime < currentTimestamp) {
                revert IDCAStrategy.InvalidFirstExecutionTime(params.firstExecutionTime, currentTimestamp);
            }
            nextExecutionTime = params.firstExecutionTime;
        }
    }

    /**
     * @notice Validates user-configurable parameters during strategy creation and updates.
     * @param targetAllocation Desired total capital allocation for the cycle.
     * @param frequency Scheduled execution interval in seconds.
     * @param maxDelay Maximum allowed delay window after nextExecutionTime in seconds.
     * @param minExecutionAmount Minimum allowed order amount.
     * @param maxExecutionAmount Maximum allowed order amount.
     */
    function validateUpdateParams(
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    ) internal pure {
        if (targetAllocation == 0) revert IDCAStrategy.ZeroTargetAllocation();
        if (frequency == 0) revert IDCAStrategy.ZeroFrequency();
        if (maxDelay == 0) revert IDCAStrategy.ZeroMaxDelay();
        if (minExecutionAmount == 0) revert IDCAStrategy.ZeroMinExecutionAmount();
        if (maxExecutionAmount == 0) revert IDCAStrategy.ZeroMaxExecutionAmount();

        if (minExecutionAmount > maxExecutionAmount) {
            revert IDCAStrategy.MinExecutionExceedsMax(minExecutionAmount, maxExecutionAmount);
        }
        if (minExecutionAmount > targetAllocation) {
            revert IDCAStrategy.MinExecutionExceedsAllocation(minExecutionAmount, targetAllocation);
        }
        if (maxExecutionAmount > targetAllocation) {
            revert IDCAStrategy.MaxExecutionExceedsAllocation(maxExecutionAmount, targetAllocation);
        }
    }

    /**
     * @notice Validates whether an amount is within the configured DCA execution bounds.
     * @param amount Proposed execution amount.
     * @param minExecutionAmount Configured minimum execution amount.
     * @param maxExecutionAmount Configured maximum execution amount.
     * @param targetAllocation Configured target allocation for the cycle.
     * @return True if amount is > 0 and within [minExecutionAmount, maxExecutionAmount] and <= targetAllocation.
     */
    function validateExecutionAmount(
        uint256 amount,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount,
        uint256 targetAllocation
    ) internal pure returns (bool) {
        if (amount == 0) return false;
        if (amount < minExecutionAmount) return false;
        if (amount > maxExecutionAmount) return false;
        if (amount > targetAllocation) return false;
        return true;
    }

    /**
     * @notice Checks if current timestamp is at or past the scheduled next execution time.
     * @param nextExecutionTime Scheduled execution timestamp.
     * @param currentTimestamp Current block timestamp.
     * @return True if `currentTimestamp >= nextExecutionTime`.
     */
    function isExecutionDue(uint256 nextExecutionTime, uint256 currentTimestamp) internal pure returns (bool) {
        return currentTimestamp >= nextExecutionTime;
    }

    /**
     * @notice Checks if current timestamp is within the allowed execution window [nextExecutionTime, nextExecutionTime + maxDelay].
     * @param nextExecutionTime Scheduled execution timestamp.
     * @param maxDelay Maximum delay grace window.
     * @param currentTimestamp Current block timestamp.
     * @return True if within the active execution window.
     */
    function isExecutionWindowOpen(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        internal
        pure
        returns (bool)
    {
        return (currentTimestamp >= nextExecutionTime && currentTimestamp <= nextExecutionTime + maxDelay);
    }

    /**
     * @notice Checks if current timestamp has exceeded the allowed max delay window.
     * @param nextExecutionTime Scheduled execution timestamp.
     * @param maxDelay Maximum delay grace window.
     * @param currentTimestamp Current block timestamp.
     * @return True if overdue (`currentTimestamp > nextExecutionTime + maxDelay`).
     */
    function isOverdue(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        internal
        pure
        returns (bool)
    {
        return currentTimestamp > nextExecutionTime + maxDelay;
    }

    /**
     * @notice Computes remaining seconds available in the delay window before the strategy becomes overdue.
     * @param nextExecutionTime Scheduled execution timestamp.
     * @param maxDelay Maximum delay grace window.
     * @param currentTimestamp Current block timestamp.
     * @return Remaining delay seconds (0 if overdue, maxDelay if before scheduled time).
     */
    function calculateRemainingDelay(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        internal
        pure
        returns (uint256)
    {
        uint256 deadline = nextExecutionTime + maxDelay;
        if (currentTimestamp > deadline) {
            return 0;
        }
        if (currentTimestamp < nextExecutionTime) {
            return maxDelay;
        }
        return deadline - currentTimestamp;
    }
}
