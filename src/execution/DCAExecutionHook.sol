// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {IExecutionManager} from "../interfaces/IExecutionManager.sol";
import {IDCAExecutionHook} from "../interfaces/IDCAExecutionHook.sol";

/**
 * @title DCAExecutionHook
 * @notice Module 7 Uniswap v4 Hook-based execution layer contract.
 * @dev Enforces swap authorization on DCA pools.
 */
contract DCAExecutionHook is IHooks, IDCAExecutionHook {
    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------
    error NotPoolManager();
    error UnauthorizedExecutor();
    error InvalidHookData();
    error HookNotImplemented();

    // -------------------------------------------------------------------------
    // IMMUTABLES
    // -------------------------------------------------------------------------
    IPoolManager public immutable override poolManager;
    address public immutable override executionManager;

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(IPoolManager _poolManager, address _executionManager) {
        if (address(_poolManager) == address(0)) revert NotPoolManager();
        if (_executionManager == address(0)) revert UnauthorizedExecutor();
        poolManager = _poolManager;
        executionManager = _executionManager;
    }

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    // -------------------------------------------------------------------------
    // IHOOKS IMPLEMENTATION
    // -------------------------------------------------------------------------

    function beforeInitialize(address, PoolKey calldata, uint160)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external virtual override onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external virtual override onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address sender, PoolKey calldata, SwapParams calldata params, bytes calldata hookData)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Get expected swap executor from ExecutionManager
        address expectedExecutor = IExecutionManager(executionManager).swapExecutor();

        if (sender != expectedExecutor) {
            revert UnauthorizedExecutor();
        }

        if (hookData.length < 32) {
            revert InvalidHookData();
        }

        uint256 strategyId = abi.decode(hookData, (uint256));
        emit DCASwapValidated(sender, strategyId, params.amountSpecified);

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}
