// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";

/**
 * @title IDCAExecutionHook
 * @notice Interface for Module 7 DCA execution hook on Uniswap v4.
 */
interface IDCAExecutionHook {
    /**
     * @notice Emitted when the hook validates a swap from the authorized executor.
     * @param sender The caller of poolManager.swap()
     * @param strategyId The strategy ID extracted from hookData
     * @param amountSpecified The swap amount
     */
    event DCASwapValidated(address indexed sender, uint256 indexed strategyId, int256 amountSpecified);

    /**
     * @notice Returns the address of the PoolManager.
     */
    function poolManager() external view returns (IPoolManager);

    /**
     * @notice Returns the address of the ExecutionManager.
     */
    function executionManager() external view returns (address);
}
