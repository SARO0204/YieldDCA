// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapExecutor} from "../interfaces/ISwapExecutor.sol";

/**
 * @title MockSwapExecutor
 * @notice Development/test implementation of ISwapExecutor.
 * @dev This is a MOCK-ONLY swap executor for local development, testing, and demonstration.
 *      It does NOT integrate with any DEX or real market.
 *      It simulates a swap by consuming inputToken and minting/returning outputToken
 *      at a configurable mock exchange rate.
 *
 *      NOT FOR PRODUCTION USE.
 *
 *      Future production path:
 *          MockSwapExecutor → UniswapV4SwapExecutor (Module 7)
 *
 *      Configurable behaviors:
 *      - mockExchangeRate: units of outputToken per 1e18 units of inputToken.
 *      - shouldFail: forces every swap to revert (tests failure path).
 *      - outputToken: the ERC-20 token produced by this mock executor.
 */
contract MockSwapExecutor is ISwapExecutor {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------

    error MockSwapForcedFailure();
    error MockExchangeRateZero();

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    event MockRateUpdated(uint256 oldRate, uint256 newRate);
    event MockFailureToggled(bool shouldFail);

    // -------------------------------------------------------------------------
    // STORAGE
    // -------------------------------------------------------------------------

    /// @notice The ERC-20 token this executor produces as swap output.
    IERC20 public immutable outputToken;

    /// @notice Simulated exchange rate: outputToken units per 1e6 inputToken units.
    ///         e.g. 1e18 means 1:1 (same decimals), 2e6 means 2 outputToken per 1 inputToken (6 decimals).
    uint256 public mockExchangeRate;

    /// @notice If true, every executeSwap call reverts (tests failure handling).
    bool public shouldFail;

    /// @notice Owner of this mock — can update rate and failure mode.
    address public immutable owner;

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    /**
     * @notice Initializes the MockSwapExecutor.
     * @param outputToken_ Address of the ERC-20 token to produce as swap output.
     * @param initialRate Exchange rate (outputToken units per 1e6 inputToken units, 6-decimal scale).
     *                    Set to 1e6 for a 1:1 mock rate when both tokens use 6 decimals.
     */
    constructor(address outputToken_, uint256 initialRate) {
        if (outputToken_ == address(0)) revert ZeroInputAmount();
        if (initialRate == 0) revert MockExchangeRateZero();
        outputToken = IERC20(outputToken_);
        mockExchangeRate = initialRate;
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "MockSwapExecutor: not owner");
        _;
    }

    // -------------------------------------------------------------------------
    // CONFIGURATION
    // -------------------------------------------------------------------------

    /**
     * @notice Updates the mock exchange rate.
     * @param newRate New exchange rate (outputToken per 1e6 inputToken).
     */
    function setMockExchangeRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert MockExchangeRateZero();
        emit MockRateUpdated(mockExchangeRate, newRate);
        mockExchangeRate = newRate;
    }

    /**
     * @notice Toggles the forced-failure mode.
     * @param _shouldFail True to make all swaps fail.
     */
    function setShouldFail(bool _shouldFail) external onlyOwner {
        shouldFail = _shouldFail;
        emit MockFailureToggled(_shouldFail);
    }

    // -------------------------------------------------------------------------
    // ISwapExecutor IMPLEMENTATION
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc ISwapExecutor
     * @dev For the mock: the caller must have approved this contract to pull inputToken,
     *      OR must have already transferred inputAmount to this contract.
     *      The mock computes output = inputAmount * mockExchangeRate / 1e6
     *      and transfers outputToken from its own balance to params.receiver.
     *
     *      This contract must hold sufficient outputToken balance for tests.
     */
    function executeSwap(SwapParams calldata params) external override returns (SwapResult memory result) {
        if (shouldFail) {
            revert MockSwapForcedFailure();
        }

        if (params.inputAmount == 0) revert ZeroInputAmount();

        // Pull inputToken from caller (ExecutionManager must have approved or transferred)
        IERC20(params.inputToken).safeTransferFrom(msg.sender, address(this), params.inputAmount);

        // Compute output: rate is outputToken-units per 1e6 inputToken-units
        uint256 outputAmount = (params.inputAmount * mockExchangeRate) / 1e6;

        // Enforce minimum output if specified
        if (params.minOutputAmount > 0 && outputAmount < params.minOutputAmount) {
            revert InsufficientOutputAmount(outputAmount, params.minOutputAmount);
        }

        // Transfer output tokens to receiver
        outputToken.safeTransfer(params.receiver, outputAmount);

        result = SwapResult({success: true, inputConsumed: params.inputAmount, outputReceived: outputAmount});

        emit SwapExecuted(
            params.strategyId, params.user, params.inputToken, params.targetToken, params.inputAmount, outputAmount
        );
    }
}
