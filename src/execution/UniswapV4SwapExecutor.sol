// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapExecutor} from "../interfaces/ISwapExecutor.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {SwapParams as V4SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";

/**
 * @title UniswapV4SwapExecutor
 * @notice Module 7 Uniswap v4 swap executor contract.
 * @dev Routes DCA execution swaps through Uniswap v4 pools.
 */
contract UniswapV4SwapExecutor is ISwapExecutor, IUnlockCallback {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------
    error OnlyPoolManager();
    error NotOwner();
    error PoolKeyNotFound(address token0, address token1);
    error InvalidPayer();

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------
    uint160 internal constant MIN_SQRT_PRICE = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970341;

    // -------------------------------------------------------------------------
    // IMMUTABLES
    // -------------------------------------------------------------------------
    IPoolManager public immutable poolManager;
    address public immutable owner;

    // -------------------------------------------------------------------------
    // STORAGE
    // -------------------------------------------------------------------------
    // mapping of currency0 => currency1 => PoolKey
    mapping(address => mapping(address => PoolKey)) public poolKeys;

    // -------------------------------------------------------------------------
    // STRUCTS
    // -------------------------------------------------------------------------
    struct CallbackData {
        SwapParams params;
        PoolKey key;
    }

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(IPoolManager _poolManager, address _owner) {
        if (address(_poolManager) == address(0)) revert OnlyPoolManager();
        if (_owner == address(0)) revert NotOwner();
        poolManager = _poolManager;
        owner = _owner;
    }

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // -------------------------------------------------------------------------
    // CONFIGURATION
    // -------------------------------------------------------------------------
    function registerPoolKey(PoolKey calldata key) external onlyOwner {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        poolKeys[token0][token1] = key;
    }

    // -------------------------------------------------------------------------
    // ISwapExecutor IMPLEMENTATION
    // -------------------------------------------------------------------------
    function executeSwap(SwapParams calldata params) external override returns (SwapResult memory result) {
        if (params.inputAmount == 0) revert ZeroInputAmount();

        // 1. Pull inputToken from the ExecutionManager (msg.sender)
        IERC20(params.inputToken).safeTransferFrom(msg.sender, address(this), params.inputAmount);

        // 2. Fetch corresponding PoolKey
        address token0 = params.inputToken;
        address token1 = params.targetToken;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        PoolKey memory key = poolKeys[token0][token1];
        if (Currency.unwrap(key.currency0) == address(0)) {
            revert PoolKeyNotFound(token0, token1);
        }

        // 3. Unlock PoolManager to perform swap and settlement
        bytes memory data = poolManager.unlock(abi.encode(CallbackData({params: params, key: key})));

        // 4. Decode results
        result = abi.decode(data, (SwapResult));

        // 5. Emit standard event
        emit SwapExecuted(
            params.strategyId,
            params.user,
            params.inputToken,
            params.targetToken,
            result.inputConsumed,
            result.outputReceived
        );
    }

    // -------------------------------------------------------------------------
    // IUNLOCKCALLBACK IMPLEMENTATION
    // -------------------------------------------------------------------------
    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        bool zeroForOne = data.params.inputToken == Currency.unwrap(data.key.currency0);

        // Specify exact input amount as negative
        int256 amountSpecified = -int256(data.params.inputAmount);

        // Price limit depending on swap direction
        uint160 sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE;

        V4SwapParams memory v4Params = V4SwapParams({
            zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Pass strategyId in hookData for DCAExecutionHook to inspect
        bytes memory hookData = abi.encode(data.params.strategyId);

        BalanceDelta delta = poolManager.swap(data.key, v4Params, hookData);

        // Check if delta matches zeroForOne and perform settlements
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        uint256 inputConsumed;
        uint256 outputReceived;

        if (zeroForOne) {
            // We spent token0, we got token1
            inputConsumed = uint256(-int256(delta0));
            outputReceived = uint256(int256(delta1));

            // Settle input token0 debt to pool
            _settleCurrency(data.key.currency0, inputConsumed);

            // Take output token1 credit to receiver
            _takeCurrency(data.key.currency1, data.params.receiver, outputReceived);
        } else {
            // We spent token1, we got token0
            inputConsumed = uint256(-int256(delta1));
            outputReceived = uint256(int256(delta0));

            // Settle input token1 debt to pool
            _settleCurrency(data.key.currency1, inputConsumed);

            // Take output token0 credit to receiver
            _takeCurrency(data.key.currency0, data.params.receiver, outputReceived);
        }

        // Enforce minOutputAmount slippage constraint
        if (data.params.minOutputAmount > 0 && outputReceived < data.params.minOutputAmount) {
            revert InsufficientOutputAmount(outputReceived, data.params.minOutputAmount);
        }

        return abi.encode(SwapResult({success: true, inputConsumed: inputConsumed, outputReceived: outputReceived}));
    }

    // -------------------------------------------------------------------------
    // INTERNAL HELPERS
    // -------------------------------------------------------------------------
    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (amount > 0) {
            // sync MUST be called before the ERC-20 transfer so PoolManager
            // can snapshot the balance and compute the delta on settle()
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _takeCurrency(Currency currency, address recipient, uint256 amount) internal {
        if (amount > 0) {
            // Withdraw token from PoolManager to recipient
            poolManager.take(currency, recipient, amount);
        }
    }
}
