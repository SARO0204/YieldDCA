// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/test/PoolSwapTest.sol";

import {DCAEngine} from "../src/DCAEngine.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {ExecutionManager} from "../src/execution/ExecutionManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {DCAExecutionHook} from "../src/execution/DCAExecutionHook.sol";
import {UniswapV4SwapExecutor} from "../src/execution/UniswapV4SwapExecutor.sol";
import {IDCAExecutionHook} from "../src/interfaces/IDCAExecutionHook.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";
import {IDecisionEngine} from "../src/interfaces/IDecisionEngine.sol";
import {IExecutionManager} from "../src/interfaces/IExecutionManager.sol";

/**
 * @title DCAExecutionHookTest
 * @notice Module 7 test suite: Uniswap v4 Hook-based DCA Execution Layer.
 *
 * Tests:
 *  1. Hook deployment and permission bit validation
 *  2. Authorized DCA swap via ExecutionManager → UniswapV4SwapExecutor → PoolManager → Hook
 *  3. Unauthorized direct swap is rejected by hook
 *  4. Direct hook call (bypassing PoolManager) is rejected
 *  5. Execution exceeding remaining allocation reverts
 *  6. Hook rejects missing hookData
 */
contract DCAExecutionHookTest is Test {
    using CurrencyLibrary for Currency;

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // sqrt(1) * 2^96
    uint256 constant INITIAL_LIQUIDITY = 1_000e18;
    uint256 constant STRATEGY_ALLOCATION = 500e18;
    uint256 constant MIN_EXECUTION = 10e18;
    uint256 constant MAX_EXECUTION = 500e18;

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------
    MockERC20 public currency0Token;
    MockERC20 public currency1Token;
    DCAEngine public dcaEngine;
    YieldVault public vault;
    ExecutionManager public executionManager;
    PoolManager public poolManager;
    DCAExecutionHook public hook;
    UniswapV4SwapExecutor public swapExecutor;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    PoolSwapTest public swapRouter;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    PoolKey public poolKey;
    uint256 public strategyId;

    // -------------------------------------------------------------------------
    // SETUP
    // -------------------------------------------------------------------------
    function setUp() public {
        // Deploy mock ERC-20 tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);

        // Sort by address — Uniswap v4 requires currency0 < currency1
        if (address(tokenA) < address(tokenB)) {
            currency0Token = tokenA;
            currency1Token = tokenB;
        } else {
            currency0Token = tokenB;
            currency1Token = tokenA;
        }

        // Deploy core DCA modules (Modules 1 & 2)
        dcaEngine = new DCAEngine();
        vault = new YieldVault(IERC20(address(currency0Token)), "DCA Vault currency0", "dvTK0", address(this));

        // Deploy Uniswap v4 PoolManager
        poolManager = new PoolManager(address(this));

        // Deploy ExecutionManager with temporary placeholder swap executor
        executionManager = new ExecutionManager(
            address(this), // initialOwner
            address(dcaEngine), // Module 1
            address(vault), // Module 2
            address(0xdEaD) // placeholder, replaced below
        );

        // Authorize ExecutionManager as vault operator
        vault.setAuthorizedOperator(address(executionManager), true);

        // Mine CREATE2 salt and deploy DCAExecutionHook at permission-valid address
        hook = DCAExecutionHook(_deployHookWithPermissions());

        // Deploy UniswapV4SwapExecutor
        swapExecutor = new UniswapV4SwapExecutor(poolManager, address(this));

        // Wire up swapExecutor in ExecutionManager
        executionManager.setSwapExecutor(address(swapExecutor));

        // Build PoolKey (fee=3000, tickSpacing=60)
        poolKey = PoolKey({
            currency0: Currency.wrap(address(currency0Token)),
            currency1: Currency.wrap(address(currency1Token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Register PoolKey in swap executor
        swapExecutor.registerPoolKey(poolKey);

        // Deploy v4-core liquidity/swap routers for test helper calls
        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
        swapRouter = new PoolSwapTest(poolManager);

        // Initialize the Uniswap v4 pool at 1:1 price
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // Seed liquidity: mint tokens, approve routers, add full-range liquidity
        currency0Token.mint(address(this), 10_000e18);
        currency1Token.mint(address(this), 10_000e18);

        currency0Token.approve(address(modifyLiquidityRouter), type(uint256).max);
        currency1Token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Full-range ticks aligned to tickSpacing=60
        int24 MIN_TICK_60 = -887220;
        int24 MAX_TICK_60 = 887220;

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: MIN_TICK_60, tickUpper: MAX_TICK_60, liquidityDelta: int256(INITIAL_LIQUIDITY), salt: 0
            }),
            new bytes(0)
        );

        // --- Alice: deposit into vault and create DCA strategy ---
        currency0Token.mint(alice, STRATEGY_ALLOCATION);
        vm.startPrank(alice);
        currency0Token.approve(address(vault), type(uint256).max);
        vault.deposit(STRATEGY_ALLOCATION, alice);

        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: address(currency0Token),
            targetToken: address(currency1Token),
            targetAllocation: STRATEGY_ALLOCATION,
            frequency: 1 days,
            maxDelay: 4 hours,
            minExecutionAmount: MIN_EXECUTION,
            maxExecutionAmount: MAX_EXECUTION,
            firstExecutionTime: 0
        });
        strategyId = dcaEngine.createStrategy(params);
        vm.stopPrank();
    }

    // =========================================================================
    // TEST 1: Hook deployment and permission bits
    // =========================================================================
    function test_HookDeploymentAndPermissionBits() public view {
        // Validate that the hook stores correct references
        assertEq(address(hook.poolManager()), address(poolManager), "PoolManager mismatch");
        assertEq(hook.executionManager(), address(executionManager), "ExecutionManager mismatch");

        // Validate BEFORE_SWAP_FLAG (bit 7 = 0x0080) is set; no other flags
        uint160 addrBits = uint160(address(hook)) & 0x3FFF;
        assertEq(addrBits, 0x0080, "Hook address must satisfy BEFORE_SWAP_FLAG only");
    }

    // =========================================================================
    // TEST 2: Authorized DCA swap via full stack
    // =========================================================================
    function test_AuthorizedSwap_FullStack() public {
        // Build a valid EXECUTE decision for 100 TK0
        uint256 execAmount = 100e18;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        // Alice approves `this` (test contract / keeper) to execute her strategy
        vm.prank(alice);
        executionManager.setStrategyExecutor(strategyId, address(this), true);

        // Capture balances before execution
        uint256 aliceCurrency1Before = currency1Token.balanceOf(alice);
        uint256 vaultSharesBefore = vault.balanceOf(alice);

        // Expect the DCASwapValidated event from the hook (topic1=executor, topic2=strategyId; don't check data)
        vm.expectEmit(true, true, false, false, address(hook));
        emit IDCAExecutionHook.DCASwapValidated(address(swapExecutor), strategyId, 0);

        // Execute via ExecutionManager (this = authorized executor)
        IExecutionManager.ExecutionResult memory result = executionManager.executeDecision(strategyId, decision, 0, 0);

        // Assert execution succeeded (executedAmount ≈ execAmount, within 1 wei AMM rounding)
        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
        assertApproxEqAbs(result.executedAmount, execAmount, 1, "executedAmount should match input within 1 wei");

        // Assert vault shares decreased (capital withdrawn for swap)
        assertLt(vault.balanceOf(alice), vaultSharesBefore, "Vault shares should decrease after execution");

        // Assert Alice received output tokens
        assertGt(currency1Token.balanceOf(alice), aliceCurrency1Before, "Alice should receive output tokens");
    }

    // =========================================================================
    // TEST 3: Unauthorized direct swap is rejected by the hook
    // =========================================================================
    function test_Revert_UnauthorizedDirectSwap() public {
        // Bob tries to swap directly on the pool bypassing ExecutionManager
        currency0Token.mint(bob, 100e18);

        vm.startPrank(bob);
        currency0Token.approve(address(swapRouter), type(uint256).max);

        // Should revert because bob != swapExecutor
        vm.expectRevert();
        swapRouter.swap(
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -10e18, sqrtPriceLimitX96: SQRT_PRICE_1_1 - 1000}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            abi.encode(uint256(1)) // hookData with strategyId
        );
        vm.stopPrank();
    }

    // =========================================================================
    // TEST 4: Direct call to hook callbacks reverts (not from PoolManager)
    // =========================================================================
    function test_Revert_DirectHookCallNotFromPoolManager() public {
        vm.expectRevert(DCAExecutionHook.NotPoolManager.selector);
        hook.beforeSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -10e18, sqrtPriceLimitX96: SQRT_PRICE_1_1}),
            new bytes(0)
        );
    }

    // =========================================================================
    // TEST 5: Execution exceeding remaining allocation reverts
    // =========================================================================
    function test_Revert_ExceedsRemainingAllocation() public {
        uint256 tooLarge = STRATEGY_ALLOCATION + 1e18;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, tooLarge);

        vm.prank(alice);
        vm.expectRevert(); // ExceedsRemainingAllocation
        executionManager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 6: Hook initialization validates addresses
    // =========================================================================
    function test_HookConstructorValidation() public {
        // Zero poolManager should revert
        vm.expectRevert(DCAExecutionHook.NotPoolManager.selector);
        new DCAExecutionHook(IPoolManager(address(0)), address(executionManager));

        // Zero executionManager should revert
        vm.expectRevert(DCAExecutionHook.UnauthorizedExecutor.selector);
        new DCAExecutionHook(poolManager, address(0));
    }

    // =========================================================================
    // TEST 7: UniswapV4SwapExecutor pool key lookup
    // =========================================================================
    function test_SwapExecutor_PoolKeyLookup() public view {
        // Verify the registered pool key via individual fields from auto-generated getter
        address t0 = address(currency0Token);
        address t1 = address(currency1Token);
        if (t0 > t1) (t0, t1) = (t1, t0);

        // The Solidity auto-getter returns (currency0, currency1, fee, tickSpacing, hooks)
        (Currency c0, Currency c1, uint24 fee, int24 tickSpacing, IHooks hooks) = swapExecutor.poolKeys(t0, t1);

        assertEq(Currency.unwrap(c0), t0, "currency0 mismatch");
        assertEq(Currency.unwrap(c1), t1, "currency1 mismatch");
        assertEq(fee, 3000, "fee mismatch");
        assertEq(tickSpacing, 60, "tickSpacing mismatch");
        assertEq(address(hooks), address(hook), "hooks mismatch");
    }

    // =========================================================================
    // INTERNAL HELPERS
    // =========================================================================

    function _buildDecision(IDecisionEngine.DecisionAction action, uint256 execAmount)
        internal
        view
        returns (IDecisionEngine.DecisionResult memory)
    {
        return IDecisionEngine.DecisionResult({
            action: action,
            targetAmount: STRATEGY_ALLOCATION,
            executionAmount: execAmount,
            remainingAmount: execAmount > STRATEGY_ALLOCATION ? 0 : STRATEGY_ALLOCATION - execAmount,
            recommendedDelay: 0,
            score: 7500,
            reason: "test decision",
            timestamp: block.timestamp,
            diagnostics: _emptyDiagnostics()
        });
    }

    function _emptyDiagnostics() internal pure returns (IDecisionEngine.DecisionDiagnostics memory) {
        return IDecisionEngine.DecisionDiagnostics({
            price: 0,
            twap: 0,
            priceDeviation: 0,
            volatility: 0,
            liquidity: 0,
            slippage: 0,
            priceImpact: 0,
            currentAPY: 0,
            estimatedWaitingYield: 0,
            opportunityCost: 0,
            waitingBenefit: 0,
            marketScore: 0,
            yieldScore: 0,
            strategyScore: 0,
            minimumExecutionSatisfied: true,
            maximumExecutionSatisfied: true,
            remainingAllocationSatisfied: true,
            capitalAvailable: true,
            delayAllowed: true,
            strategyActive: true
        });
    }

    /**
     * @notice Mine a CREATE2 salt such that the deployed DCAExecutionHook address
     *         satisfies the BEFORE_SWAP_FLAG (bit 7 = 0x0080) permission requirement.
     */
    function _deployHookWithPermissions() internal returns (address) {
        bytes memory bytecode =
            abi.encodePacked(type(DCAExecutionHook).creationCode, abi.encode(poolManager, address(executionManager)));
        bytes32 initCodeHash = keccak256(bytecode);

        uint256 salt = 0;
        address hookAddress;

        // Mine until we find an address where bits[13:0] == BEFORE_SWAP_FLAG (0x0080)
        while (true) {
            hookAddress = vm.computeCreate2Address(bytes32(salt), initCodeHash, address(this));
            if (uint160(hookAddress) & 0x3FFF == 0x0080) {
                break;
            }
            unchecked {
                ++salt;
            }
        }

        address deployed;
        assembly ("memory-safe") {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(deployed != address(0), "Hook CREATE2 deployment failed");
        require(deployed == hookAddress, "Hook address mismatch");
        return deployed;
    }
}
