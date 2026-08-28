// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISwapExecutor
 * @notice Abstraction interface for the swap execution layer consumed by Module 6: ExecutionManager.
 * @dev Separates swap mechanism from execution orchestration.
 *      Current implementation: MockSwapExecutor for local development and testing.
 *      Future implementation: UniswapV4SwapExecutor (Module 7).
 *
 *      Architecture:
 *          ExecutionManager (Module 6)
 *                  │
 *                  ▼
 *           ISwapExecutor
 *                  │
 *          ┌───────┴────────┐
 *          │                │
 *   MockSwapExecutor    UniswapV4SwapExecutor (future)
 */
interface ISwapExecutor {
    // -------------------------------------------------------------------------
    // STRUCTS
    // -------------------------------------------------------------------------

    /**
     * @notice Parameters passed to the swap executor for a single swap order.
     * @param strategyId Unique identifier of the DCA strategy requesting the swap.
     * @param user Address of the strategy owner (tokens originate from their vault shares).
     * @param inputToken Address of the ERC-20 token being sold/spent.
     * @param targetToken Address of the ERC-20 token being bought/acquired.
     * @param inputAmount Exact amount of inputToken to swap.
     * @param minOutputAmount Minimum acceptable output amount (0 = no slippage protection).
     * @param receiver Address that receives the acquired targetToken.
     */
    struct SwapParams {
        uint256 strategyId;
        address user;
        address inputToken;
        address targetToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        address receiver;
    }

    /**
     * @notice Result returned after swap execution attempt.
     * @param success True if the swap completed successfully.
     * @param inputConsumed Actual amount of inputToken consumed by the swap.
     * @param outputReceived Actual amount of targetToken received from the swap.
     */
    struct SwapResult {
        bool success;
        uint256 inputConsumed;
        uint256 outputReceived;
    }

    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------

    /// @notice Emitted when swap fails with zero output.
    error SwapFailed(uint256 strategyId, uint256 inputAmount);

    /// @notice Emitted when output is below the caller's minimum acceptable amount.
    error InsufficientOutputAmount(uint256 received, uint256 minimum);

    /// @notice Emitted when input amount is zero.
    error ZeroInputAmount();

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when a swap is executed.
     * @param strategyId The strategy that triggered the swap.
     * @param user Strategy owner address.
     * @param inputToken Token sold.
     * @param targetToken Token acquired.
     * @param inputConsumed Amount of inputToken consumed.
     * @param outputReceived Amount of targetToken received.
     */
    event SwapExecuted(
        uint256 indexed strategyId,
        address indexed user,
        address indexed inputToken,
        address targetToken,
        uint256 inputConsumed,
        uint256 outputReceived
    );

    // -------------------------------------------------------------------------
    // EXECUTION
    // -------------------------------------------------------------------------

    /**
     * @notice Executes a token swap according to the provided parameters.
     * @dev Must revert if swap fails or output is below minOutputAmount.
     *      The caller (ExecutionManager) must have already transferred inputAmount
     *      of inputToken to this contract before calling.
     * @param params The swap parameters.
     * @return result Detailed result of the swap execution.
     */
    function executeSwap(SwapParams calldata params) external returns (SwapResult memory result);
}
