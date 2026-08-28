// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDCAStrategy} from "./interfaces/IDCAStrategy.sol";
import {DCAStrategyLib} from "./libraries/DCAStrategyLib.sol";

/**
 * @title DCAEngine
 * @notice Core implementation of Module 1: DCA Strategy Management.
 * @dev Manages creation, storage, configuration updates, lifecycle state transitions,
 *      and execution constraint validation for user DCA strategies.
 *
 * Architectural Boundary:
 * - Module 1 stores user intent, constraints, and scheduling states.
 * - Module 1 NEVER moves funds, interacts with ERC-4626 vaults, performs DEX swaps,
 *   fetches market/oracle data, or makes execution decisions.
 * - Module 1 NEVER transitions a strategy to COMPLETED (reserved for future accounting modules).
 */
contract DCAEngine is IDCAStrategy {
    // ------------------------------------------------------------------------
    // STORAGE
    // ------------------------------------------------------------------------

    /// @notice Monotonically increasing strategy identifier tracker.
    uint256 private _strategyCounter;

    /// @notice Mapping from unique strategy ID to Strategy configuration.
    mapping(uint256 => Strategy) private _strategies;

    /// @notice Mapping from user address to list of owned strategy IDs.
    mapping(address => uint256[]) private _userStrategies;

    // ------------------------------------------------------------------------
    // MODIFIERS & INTERNAL GUARDS
    // ------------------------------------------------------------------------

    /**
     * @dev Ensures caller is the owner of the strategy and strategy exists.
     * @param strategyId Unique ID of the strategy.
     */
    modifier onlyStrategyOwner(uint256 strategyId) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status == StrategyStatus.NONE) {
            revert StrategyNotFound(strategyId);
        }
        if (msg.sender != strategy.owner) {
            revert NotStrategyOwner(strategyId, msg.sender, strategy.owner);
        }
        _;
    }

    // ------------------------------------------------------------------------
    // STRATEGY LIFECYCLE MANAGEMENT (MUTATING)
    // ------------------------------------------------------------------------

    /// @inheritdoc IDCAStrategy
    function createStrategy(StrategyParams calldata params) external returns (uint256 strategyId) {
        uint256 nextExecutionTime = DCAStrategyLib.validateStrategyParams(params, block.timestamp);

        unchecked {
            strategyId = ++_strategyCounter;
        }

        _strategies[strategyId] = Strategy({
            owner: msg.sender,
            inputToken: params.inputToken,
            targetToken: params.targetToken,
            targetAllocation: params.targetAllocation,
            frequency: params.frequency,
            maxDelay: params.maxDelay,
            minExecutionAmount: params.minExecutionAmount,
            maxExecutionAmount: params.maxExecutionAmount,
            nextExecutionTime: nextExecutionTime,
            status: StrategyStatus.ACTIVE
        });

        _userStrategies[msg.sender].push(strategyId);

        emit StrategyCreated(
            strategyId,
            msg.sender,
            params.inputToken,
            params.targetToken,
            params.targetAllocation,
            params.frequency,
            params.maxDelay,
            params.minExecutionAmount,
            params.maxExecutionAmount,
            nextExecutionTime
        );
    }

    /// @inheritdoc IDCAStrategy
    function updateStrategy(
        uint256 strategyId,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    ) external onlyStrategyOwner(strategyId) {
        Strategy storage strategy = _strategies[strategyId];

        if (strategy.status == StrategyStatus.CANCELLED) {
            revert StrategyAlreadyCancelled(strategyId);
        }

        DCAStrategyLib.validateUpdateParams(
            targetAllocation, frequency, maxDelay, minExecutionAmount, maxExecutionAmount
        );

        strategy.targetAllocation = targetAllocation;
        strategy.frequency = frequency;
        strategy.maxDelay = maxDelay;
        strategy.minExecutionAmount = minExecutionAmount;
        strategy.maxExecutionAmount = maxExecutionAmount;

        emit StrategyUpdated(
            strategyId, msg.sender, targetAllocation, frequency, maxDelay, minExecutionAmount, maxExecutionAmount
        );
    }

    /// @inheritdoc IDCAStrategy
    function pauseStrategy(uint256 strategyId) external onlyStrategyOwner(strategyId) {
        Strategy storage strategy = _strategies[strategyId];

        if (strategy.status != StrategyStatus.ACTIVE) {
            revert InvalidStrategyStatus(strategyId, strategy.status, StrategyStatus.ACTIVE);
        }

        strategy.status = StrategyStatus.PAUSED;
        emit StrategyPaused(strategyId, msg.sender);
    }

    /// @inheritdoc IDCAStrategy
    function resumeStrategy(uint256 strategyId) external onlyStrategyOwner(strategyId) {
        Strategy storage strategy = _strategies[strategyId];

        if (strategy.status != StrategyStatus.PAUSED) {
            revert InvalidStrategyStatus(strategyId, strategy.status, StrategyStatus.PAUSED);
        }

        strategy.status = StrategyStatus.ACTIVE;
        emit StrategyResumed(strategyId, msg.sender);
    }

    /// @inheritdoc IDCAStrategy
    function cancelStrategy(uint256 strategyId) external onlyStrategyOwner(strategyId) {
        Strategy storage strategy = _strategies[strategyId];

        if (strategy.status == StrategyStatus.CANCELLED) {
            revert StrategyAlreadyCancelled(strategyId);
        }

        strategy.status = StrategyStatus.CANCELLED;
        emit StrategyCancelled(strategyId, msg.sender);
    }

    // ------------------------------------------------------------------------
    // QUERIES & GETTERS
    // ------------------------------------------------------------------------

    /// @inheritdoc IDCAStrategy
    function getStrategy(uint256 strategyId) external view returns (Strategy memory strategy) {
        strategy = _strategies[strategyId];
        if (strategy.status == StrategyStatus.NONE) {
            revert StrategyNotFound(strategyId);
        }
    }

    /// @inheritdoc IDCAStrategy
    function getUserStrategies(address user) external view returns (uint256[] memory strategyIds) {
        return _userStrategies[user];
    }

    /// @inheritdoc IDCAStrategy
    function getStrategyCount() external view returns (uint256 count) {
        return _strategyCounter;
    }

    // ------------------------------------------------------------------------
    // EXECUTION & SCHEDULING SUPPORT (READ-ONLY)
    // ------------------------------------------------------------------------

    /// @inheritdoc IDCAStrategy
    function isExecutionDue(uint256 strategyId) external view returns (bool isDue) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status != StrategyStatus.ACTIVE) {
            return false;
        }
        return DCAStrategyLib.isExecutionDue(strategy.nextExecutionTime, block.timestamp);
    }

    /// @inheritdoc IDCAStrategy
    function isExecutionWindowOpen(uint256 strategyId) external view returns (bool isOpen) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status != StrategyStatus.ACTIVE) {
            return false;
        }
        return DCAStrategyLib.isExecutionWindowOpen(strategy.nextExecutionTime, strategy.maxDelay, block.timestamp);
    }

    /// @inheritdoc IDCAStrategy
    function isOverdue(uint256 strategyId) external view returns (bool overdue) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status != StrategyStatus.ACTIVE) {
            return false;
        }
        return DCAStrategyLib.isOverdue(strategy.nextExecutionTime, strategy.maxDelay, block.timestamp);
    }

    /// @inheritdoc IDCAStrategy
    function getRemainingDelay(uint256 strategyId) external view returns (uint256 remainingSeconds) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status == StrategyStatus.NONE) {
            revert StrategyNotFound(strategyId);
        }
        return DCAStrategyLib.calculateRemainingDelay(strategy.nextExecutionTime, strategy.maxDelay, block.timestamp);
    }

    /// @inheritdoc IDCAStrategy
    function isValidExecutionAmount(uint256 strategyId, uint256 amount) external view returns (bool isValid) {
        Strategy storage strategy = _strategies[strategyId];
        if (strategy.status != StrategyStatus.ACTIVE) {
            return false;
        }
        return DCAStrategyLib.validateExecutionAmount(
            amount, strategy.minExecutionAmount, strategy.maxExecutionAmount, strategy.targetAllocation
        );
    }
}
