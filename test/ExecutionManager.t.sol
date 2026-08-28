// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExecutionManager} from "../src/execution/ExecutionManager.sol";
import {IExecutionManager} from "../src/interfaces/IExecutionManager.sol";
import {IDecisionEngine} from "../src/interfaces/IDecisionEngine.sol";
import {ISwapExecutor} from "../src/interfaces/ISwapExecutor.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";
import {IYieldVault} from "../src/interfaces/IYieldVault.sol";
import {DCAEngine} from "../src/DCAEngine.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapExecutor} from "../src/mocks/MockSwapExecutor.sol";

/**
 * @title ExecutionManagerTest
 * @notice Comprehensive test suite for Module 6: ExecutionManager.
 * @dev Deploys real DCAEngine, YieldVault, MockERC20, and MockSwapExecutor
 *      to fully test the execution lifecycle against live contract interactions.
 */
contract ExecutionManagerTest is Test {
    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------

    MockERC20 public usdc;
    MockERC20 public weth;
    DCAEngine public dcaEngine;
    YieldVault public vault;
    MockSwapExecutor public swapExecutor;
    ExecutionManager public manager;

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public keeper = address(0x4EE9);

    uint256 public strategyId;

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    uint256 constant INITIAL_USDC = 100_000e6;
    uint256 constant TARGET_ALLOCATION = 10_000e6;
    uint256 constant MIN_EXECUTION = 100e6;
    uint256 constant MAX_EXECUTION = 10_000e6;
    uint256 constant FREQUENCY = 1 days;
    uint256 constant MAX_DELAY = 4 hours;

    // -------------------------------------------------------------------------
    // SETUP
    // -------------------------------------------------------------------------

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy Module 1: DCAEngine
        dcaEngine = new DCAEngine();

        // Deploy Module 2: YieldVault
        vault = new YieldVault(IERC20(address(usdc)), "Yield DCA Vault Share", "ydcaUSDC", deployer);

        // Deploy MockSwapExecutor with 1:1 rate for USDC→WETH mock
        // Rate: 1e6 = 1:1 (both amounts stay same when 6 decimal input)
        swapExecutor = new MockSwapExecutor(address(weth), 1e6);

        // Deploy Module 6: ExecutionManager
        manager = new ExecutionManager(deployer, address(dcaEngine), address(vault), address(swapExecutor));

        // Authorize ExecutionManager as vault operator
        vault.setAuthorizedOperator(address(manager), true);

        // Fund Alice with USDC
        usdc.mint(alice, INITIAL_USDC);

        // Alice deposits into vault
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_USDC);
        vault.deposit(INITIAL_USDC, alice);
        vm.stopPrank();

        // Alice creates a strategy
        vm.prank(alice);
        strategyId = dcaEngine.createStrategy(
            IDCAStrategy.StrategyParams({
                inputToken: address(usdc),
                targetToken: address(weth),
                targetAllocation: TARGET_ALLOCATION,
                frequency: FREQUENCY,
                maxDelay: MAX_DELAY,
                minExecutionAmount: MIN_EXECUTION,
                maxExecutionAmount: MAX_EXECUTION,
                firstExecutionTime: 0
            })
        );

        // Fund swap executor with output tokens (WETH)
        weth.mint(address(swapExecutor), 1_000_000e18);
    }

    // -------------------------------------------------------------------------
    // HELPERS
    // -------------------------------------------------------------------------

    function _buildDecision(IDecisionEngine.DecisionAction action, uint256 executionAmount)
        internal
        view
        returns (IDecisionEngine.DecisionResult memory)
    {
        return _buildDecisionWithDelay(action, executionAmount, 0);
    }

    function _buildDecisionWithDelay(IDecisionEngine.DecisionAction action, uint256 executionAmount, uint256 delay)
        internal
        view
        returns (IDecisionEngine.DecisionResult memory)
    {
        return IDecisionEngine.DecisionResult({
            action: action,
            targetAmount: TARGET_ALLOCATION,
            executionAmount: executionAmount,
            remainingAmount: executionAmount > TARGET_ALLOCATION ? 0 : TARGET_ALLOCATION - executionAmount,
            recommendedDelay: delay,
            score: 7000,
            reason: "test",
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

    // =========================================================================
    // TEST 1: SUCCESSFUL FULL EXECUTION
    // =========================================================================

    function test_SuccessfulFullExecution() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, TARGET_ALLOCATION);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
        assertEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.EXECUTE));
        assertEq(result.executedAmount, TARGET_ALLOCATION);
        assertEq(result.withdrawnAmount, TARGET_ALLOCATION);
        assertEq(result.remainingAllocation, 0);
        assertEq(result.nonce, 0);
        assertEq(result.timestamp, block.timestamp);
    }

    // =========================================================================
    // TEST 2: SUCCESSFUL PARTIAL EXECUTION
    // =========================================================================

    function test_SuccessfulPartialExecution() public {
        uint256 partialAmount = 6_000e6;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.PARTIAL_EXECUTION, partialAmount);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
        assertEq(result.executedAmount, partialAmount);
        assertEq(result.remainingAllocation, TARGET_ALLOCATION - partialAmount);
    }

    // =========================================================================
    // TEST 3: DELAY PERFORMS NO WITHDRAWAL
    // =========================================================================

    function test_DelayPerformsNoWithdrawal() public {
        uint256 vaultBefore = usdc.balanceOf(address(vault));

        IDecisionEngine.DecisionResult memory decision =
            _buildDecisionWithDelay(IDecisionEngine.DecisionAction.DELAY, 0, 3600);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.DELAYED));
        assertEq(result.executedAmount, 0);
        assertEq(result.withdrawnAmount, 0);
        assertEq(result.swapOutputAmount, 0);
        assertEq(result.remainingAllocation, TARGET_ALLOCATION);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore);
    }

    // =========================================================================
    // TEST 4: UNAUTHORIZED CALLER
    // =========================================================================

    function test_RevertUnauthorizedCaller() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, TARGET_ALLOCATION);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.UnauthorizedExecutor.selector, strategyId, bob));
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 5: NON-EXISTENT STRATEGY
    // =========================================================================

    function test_RevertNonExistentStrategy() public {
        uint256 badId = 999;
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyNotFound.selector, badId));
        manager.executeDecision(badId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 6: INACTIVE (PAUSED) STRATEGY
    // =========================================================================

    function test_RevertPausedStrategy() public {
        vm.prank(alice);
        dcaEngine.pauseStrategy(strategyId);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.StrategyNotActive.selector, strategyId));
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 7: CANCELLED STRATEGY
    // =========================================================================

    function test_RevertCancelledStrategy() public {
        vm.prank(alice);
        dcaEngine.cancelStrategy(strategyId);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.StrategyNotActive.selector, strategyId));
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 8: ZERO EXECUTION AMOUNT
    // =========================================================================

    function test_RevertZeroExecutionAmount() public {
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.ZeroExecutionAmount.selector, strategyId));
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 9: EXECUTION BELOW MINIMUM
    // =========================================================================

    function test_RevertBelowMinimumExecution() public {
        uint256 tooSmall = MIN_EXECUTION - 1;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, tooSmall);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutionManager.BelowMinimumExecution.selector, strategyId, tooSmall, MIN_EXECUTION
            )
        );
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 10: EXECUTION ABOVE MAXIMUM
    // =========================================================================

    function test_RevertAboveMaximumExecution() public {
        // Create a strategy with a smaller max
        vm.prank(alice);
        uint256 smallMaxStrategyId = dcaEngine.createStrategy(
            IDCAStrategy.StrategyParams({
                inputToken: address(usdc),
                targetToken: address(weth),
                targetAllocation: 20_000e6,
                frequency: FREQUENCY,
                maxDelay: MAX_DELAY,
                minExecutionAmount: 100e6,
                maxExecutionAmount: 5_000e6,
                firstExecutionTime: 0
            })
        );

        uint256 tooLarge = 5_001e6;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, tooLarge);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutionManager.AboveMaximumExecution.selector, smallMaxStrategyId, tooLarge, 5_000e6
            )
        );
        manager.executeDecision(smallMaxStrategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 11: EXECUTION ABOVE REMAINING ALLOCATION
    // =========================================================================

    function test_RevertExceedsRemainingAllocation() public {
        // Execute most of the allocation first
        IDecisionEngine.DecisionResult memory firstDecision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 9_000e6);
        vm.prank(alice);
        manager.executeDecision(strategyId, firstDecision, 0, 0);

        // Now try to execute more than remaining (1,000)
        IDecisionEngine.DecisionResult memory secondDecision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 2_000e6);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionManager.ExceedsRemainingAllocation.selector, strategyId, 2_000e6, 1_000e6)
        );
        manager.executeDecision(strategyId, secondDecision, 1, 0);
    }

    // =========================================================================
    // TEST 12: INSUFFICIENT VAULT FUNDS
    // =========================================================================

    function test_RevertInsufficientVaultFunds() public {
        // Create a new user (bob) with a strategy but no vault deposit
        usdc.mint(bob, 1_000e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), 500e6);
        vault.deposit(500e6, bob);

        uint256 bobStrategyId = dcaEngine.createStrategy(
            IDCAStrategy.StrategyParams({
                inputToken: address(usdc),
                targetToken: address(weth),
                targetAllocation: TARGET_ALLOCATION,
                frequency: FREQUENCY,
                maxDelay: MAX_DELAY,
                minExecutionAmount: MIN_EXECUTION,
                maxExecutionAmount: MAX_EXECUTION,
                firstExecutionTime: 0
            })
        );
        vm.stopPrank();

        // Bob tries to execute more than the vault holds for his shares
        // The vault total has alice's deposit (100k) + bob's (500), but bob only has 500 in shares
        // We'll drain the vault first to create insufficient liquidity scenario
        // Actually let's test it more simply - bob deposits 500 but tries to execute 1000
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        // This will fail at the vault level because bob doesn't have enough shares
        vm.prank(bob);
        vm.expectRevert(); // Will revert with InsufficientUserShares from vault
        manager.executeDecision(bobStrategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 13: STALE DECISION
    // =========================================================================

    function test_RevertStaleDecision() public {
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        // Advance time past maxDecisionAge
        vm.warp(block.timestamp + 301);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionManager.StaleDecision.selector, decision.timestamp, block.timestamp, 300)
        );
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 14: REPLAY PROTECTION (INVALID NONCE)
    // =========================================================================

    function test_RevertReplayWithInvalidNonce() public {
        // Execute once
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);
        vm.prank(alice);
        manager.executeDecision(strategyId, decision, 0, 0);

        // Try replaying with old nonce (0)
        IDecisionEngine.DecisionResult memory decision2 =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.InvalidNonce.selector, strategyId, 0, 1));
        manager.executeDecision(strategyId, decision2, 0, 0);
    }

    // =========================================================================
    // TEST 15: SUCCESSFUL SWAP
    // =========================================================================

    function test_SuccessfulSwap_OutputReceived() public {
        uint256 execAmount = 5_000e6;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        // With 1:1 rate, output should equal input
        assertEq(result.swapOutputAmount, execAmount);
        // Alice should have received WETH
        assertEq(weth.balanceOf(alice), execAmount);
    }

    // =========================================================================
    // TEST 16: FAILED SWAP
    // =========================================================================

    function test_RevertFailedSwap() public {
        // Enable failure mode
        swapExecutor.setShouldFail(true);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(); // MockSwapForcedFailure or transaction revert
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 17: ACCOUNTING AFTER SUCCESSFUL EXECUTION
    // =========================================================================

    function test_AccountingAfterExecution() public {
        uint256 execAmount = 3_000e6;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        manager.executeDecision(strategyId, decision, 0, 0);

        IExecutionManager.ExecutionRecord memory record = manager.getExecutionRecord(strategyId);
        assertEq(record.totalExecuted, execAmount);
        assertEq(record.lastExecutionAmount, execAmount);
        assertEq(record.executionCount, 1);
        assertEq(record.nonce, 1);
        assertEq(record.lastExecutionTimestamp, block.timestamp);
    }

    // =========================================================================
    // TEST 18: ACCOUNTING UNCHANGED AFTER FAILED EXECUTION
    // =========================================================================

    function test_AccountingUnchangedAfterFailedExecution() public {
        swapExecutor.setShouldFail(true);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(alice);
        vm.expectRevert();
        manager.executeDecision(strategyId, decision, 0, 0);

        // Accounting should be untouched
        IExecutionManager.ExecutionRecord memory record = manager.getExecutionRecord(strategyId);
        assertEq(record.totalExecuted, 0);
        assertEq(record.executionCount, 0);
        assertEq(record.nonce, 0);
    }

    // =========================================================================
    // TEST 19: EXACT VAULT WITHDRAWAL AMOUNT
    // =========================================================================

    function test_ExactVaultWithdrawalAmount() public {
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        uint256 execAmount = 6_000e6;

        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        uint256 vaultAfter = usdc.balanceOf(address(vault));
        assertEq(result.withdrawnAmount, execAmount);
        assertEq(vaultBefore - vaultAfter, execAmount);
    }

    // =========================================================================
    // TEST 20: PARTIAL EXECUTION LEAVES CORRECT REMAINING
    // =========================================================================

    function test_PartialExecutionCorrectRemaining() public {
        uint256 firstExec = 4_000e6;
        IDecisionEngine.DecisionResult memory decision1 =
            _buildDecision(IDecisionEngine.DecisionAction.PARTIAL_EXECUTION, firstExec);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory r1 = manager.executeDecision(strategyId, decision1, 0, 0);
        assertEq(r1.remainingAllocation, TARGET_ALLOCATION - firstExec);

        uint256 remaining = manager.getRemainingAllocation(strategyId);
        assertEq(remaining, TARGET_ALLOCATION - firstExec);
    }

    // =========================================================================
    // TEST 21: MULTIPLE SEQUENTIAL EXECUTIONS
    // =========================================================================

    function test_MultipleSequentialExecutions() public {
        uint256 exec1 = 2_000e6;
        uint256 exec2 = 3_000e6;
        uint256 exec3 = 5_000e6;

        // First execution
        IDecisionEngine.DecisionResult memory d1 =
            _buildDecision(IDecisionEngine.DecisionAction.PARTIAL_EXECUTION, exec1);
        vm.prank(alice);
        manager.executeDecision(strategyId, d1, 0, 0);

        // Second execution
        IDecisionEngine.DecisionResult memory d2 =
            _buildDecision(IDecisionEngine.DecisionAction.PARTIAL_EXECUTION, exec2);
        vm.prank(alice);
        manager.executeDecision(strategyId, d2, 1, 0);

        // Third execution (completes the allocation)
        IDecisionEngine.DecisionResult memory d3 = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, exec3);
        vm.prank(alice);
        IExecutionManager.ExecutionResult memory r3 = manager.executeDecision(strategyId, d3, 2, 0);

        assertEq(r3.remainingAllocation, 0);
        assertEq(manager.getRemainingAllocation(strategyId), 0);

        IExecutionManager.ExecutionRecord memory record = manager.getExecutionRecord(strategyId);
        assertEq(record.totalExecuted, exec1 + exec2 + exec3);
        assertEq(record.executionCount, 3);
        assertEq(record.nonce, 3);
    }

    // =========================================================================
    // TEST 22: BOUNDARY - MINIMUM EXECUTION AMOUNT
    // =========================================================================

    function test_BoundaryMinimumExecutionAmount() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, MIN_EXECUTION);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
        assertEq(result.executedAmount, MIN_EXECUTION);
    }

    // =========================================================================
    // TEST 23: BOUNDARY - MAXIMUM EXECUTION AMOUNT
    // =========================================================================

    function test_BoundaryMaximumExecutionAmount() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, MAX_EXECUTION);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
        assertEq(result.executedAmount, MAX_EXECUTION);
    }

    // =========================================================================
    // TEST 24: AUTHORIZED EXECUTOR (KEEPER)
    // =========================================================================

    function test_AuthorizedExecutorCanExecute() public {
        // Alice authorizes keeper
        vm.prank(alice);
        manager.setStrategyExecutor(strategyId, keeper, true);

        assertTrue(manager.isAuthorizedExecutor(strategyId, keeper));

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(keeper);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
    }

    // =========================================================================
    // TEST 25: REVOKED EXECUTOR CANNOT EXECUTE
    // =========================================================================

    function test_RevokedExecutorCannotExecute() public {
        vm.prank(alice);
        manager.setStrategyExecutor(strategyId, keeper, true);

        vm.prank(alice);
        manager.setStrategyExecutor(strategyId, keeper, false);

        assertFalse(manager.isAuthorizedExecutor(strategyId, keeper));

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.UnauthorizedExecutor.selector, strategyId, keeper));
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 26: ONLY STRATEGY OWNER CAN SET EXECUTOR
    // =========================================================================

    function test_RevertNonOwnerSetExecutor() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.UnauthorizedExecutor.selector, strategyId, bob));
        manager.setStrategyExecutor(strategyId, keeper, true);
    }

    // =========================================================================
    // TEST 27: DELAY ADVANCES NONCE
    // =========================================================================

    function test_DelayAdvancesNonce() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecisionWithDelay(IDecisionEngine.DecisionAction.DELAY, 0, 3600);

        assertEq(manager.getExecutionNonce(strategyId), 0);

        vm.prank(alice);
        manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(manager.getExecutionNonce(strategyId), 1);
    }

    // =========================================================================
    // TEST 28: SWAP EXECUTOR UPDATE (OWNER ONLY)
    // =========================================================================

    function test_SetSwapExecutor() public {
        MockSwapExecutor newExecutor = new MockSwapExecutor(address(weth), 2e6);
        manager.setSwapExecutor(address(newExecutor));
        assertEq(manager.swapExecutor(), address(newExecutor));
    }

    function test_RevertSetSwapExecutorNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.setSwapExecutor(address(1));
    }

    function test_RevertSetSwapExecutorZero() public {
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.ZeroAddress.selector));
        manager.setSwapExecutor(address(0));
    }

    // =========================================================================
    // TEST 29: MAX DECISION AGE UPDATE
    // =========================================================================

    function test_SetMaxDecisionAge() public {
        manager.setMaxDecisionAge(600);
        assertEq(manager.maxDecisionAge(), 600);
    }

    function test_MaxDecisionAgeZeroDisablesCheck() public {
        manager.setMaxDecisionAge(0);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        // Advance time far into the future
        vm.warp(block.timestamp + 365 days);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(uint256(result.status), uint256(IExecutionManager.ExecutionStatus.SUCCESS));
    }

    // =========================================================================
    // TEST 30: CONSTRUCTOR VALIDATIONS
    // =========================================================================

    function test_RevertConstructorZeroDCAEngine() public {
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.ZeroAddress.selector));
        new ExecutionManager(deployer, address(0), address(vault), address(swapExecutor));
    }

    function test_RevertConstructorZeroVault() public {
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.ZeroAddress.selector));
        new ExecutionManager(deployer, address(dcaEngine), address(0), address(swapExecutor));
    }

    function test_RevertConstructorZeroSwapExecutor() public {
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.ZeroAddress.selector));
        new ExecutionManager(deployer, address(dcaEngine), address(vault), address(0));
    }

    // =========================================================================
    // TEST 31: REMAINING ALLOCATION QUERY
    // =========================================================================

    function test_GetRemainingAllocationInitial() public view {
        assertEq(manager.getRemainingAllocation(strategyId), TARGET_ALLOCATION);
    }

    function test_GetRemainingAllocationAfterExecution() public {
        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 7_000e6);

        vm.prank(alice);
        manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(manager.getRemainingAllocation(strategyId), 3_000e6);
    }

    // =========================================================================
    // TEST 32: EXECUTION EVENTS
    // =========================================================================

    function test_EmitsExecutionEvents() public {
        uint256 execAmount = 5_000e6;
        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IExecutionManager.ExecutionRequested(
            strategyId, alice, IDecisionEngine.DecisionAction.EXECUTE, execAmount, 0
        );
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    function test_EmitsDelayEvent() public {
        IDecisionEngine.DecisionResult memory decision =
            _buildDecisionWithDelay(IDecisionEngine.DecisionAction.DELAY, 0, 3600);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit IExecutionManager.ExecutionDelayed(strategyId, 3600, 0);
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // TEST 33: EXECUTION CANNOT EXCEED VAULT BALANCE
    // =========================================================================

    function test_ExecutionCannotExceedVaultBalance() public {
        // Drain most of vault by having alice withdraw
        vm.startPrank(alice);
        vault.withdraw(99_500e6, alice, alice);
        vm.stopPrank();

        // Now vault only has ~500 USDC
        uint256 vaultBal = usdc.balanceOf(address(vault));
        assertTrue(vaultBal < 1_000e6);

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 5_000e6);

        vm.prank(alice);
        vm.expectRevert(); // InsufficientVaultFunds or InsufficientUserShares
        manager.executeDecision(strategyId, decision, 0, 0);
    }

    // =========================================================================
    // FUZZ TEST 1: EXECUTION AMOUNT INVARIANTS
    // =========================================================================

    function testFuzz_ExecutionAmountInvariants(uint256 execAmount) public {
        // Bound to valid range
        execAmount = bound(execAmount, MIN_EXECUTION, MAX_EXECUTION);
        // Also bound to target allocation
        if (execAmount > TARGET_ALLOCATION) execAmount = TARGET_ALLOCATION;

        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        // Invariants
        assertGt(result.executedAmount, 0, "executedAmount > 0");
        assertGe(result.executedAmount, MIN_EXECUTION, "executedAmount >= min");
        assertLe(result.executedAmount, MAX_EXECUTION, "executedAmount <= max");
        assertLe(result.executedAmount, TARGET_ALLOCATION, "executedAmount <= targetAllocation");
        assertEq(result.remainingAllocation, TARGET_ALLOCATION - result.executedAmount, "remaining = target - executed");
        assertEq(result.withdrawnAmount, result.executedAmount, "withdrawn == executed");
    }

    // =========================================================================
    // FUZZ TEST 2: EXECUTION NEVER VIOLATES HARD CONSTRAINTS
    // =========================================================================

    function testFuzz_NeverViolatesConstraints(
        uint256 execAmount,
        uint256 targetAlloc,
        uint256 minExec,
        uint256 maxExec
    ) public {
        // Bound parameters to reasonable ranges
        targetAlloc = bound(targetAlloc, 1_000e6, 1_000_000e6);
        minExec = bound(minExec, 1e6, targetAlloc / 2);
        maxExec = bound(maxExec, minExec, targetAlloc);
        execAmount = bound(execAmount, minExec, maxExec);
        if (execAmount > targetAlloc) execAmount = targetAlloc;

        // Mint and deposit enough
        usdc.mint(alice, targetAlloc);
        vm.startPrank(alice);
        usdc.approve(address(vault), targetAlloc);
        vault.deposit(targetAlloc, alice);

        uint256 fuzzStrategyId = dcaEngine.createStrategy(
            IDCAStrategy.StrategyParams({
                inputToken: address(usdc),
                targetToken: address(weth),
                targetAllocation: targetAlloc,
                frequency: FREQUENCY,
                maxDelay: MAX_DELAY,
                minExecutionAmount: minExec,
                maxExecutionAmount: maxExec,
                firstExecutionTime: 0
            })
        );
        vm.stopPrank();

        IDecisionEngine.DecisionResult memory decision =
            _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, execAmount);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(fuzzStrategyId, decision, 0, 0);

        // Hard invariants
        assertGe(result.executedAmount, minExec, "must be >= minExec");
        assertLe(result.executedAmount, maxExec, "must be <= maxExec");
        assertLe(result.executedAmount, targetAlloc, "must be <= targetAlloc");
        assertEq(result.remainingAllocation, targetAlloc - result.executedAmount, "remaining must be exact");
    }

    // =========================================================================
    // FUZZ TEST 3: UNAUTHORIZED ADDRESS NEVER CAUSES WITHDRAWAL
    // =========================================================================

    function testFuzz_UnauthorizedNeverWithdraws(address attacker) public {
        vm.assume(attacker != alice);
        vm.assume(attacker != address(0));
        vm.assume(attacker != deployer);

        uint256 vaultBefore = usdc.balanceOf(address(vault));

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        vm.prank(attacker);
        vm.expectRevert();
        manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(usdc.balanceOf(address(vault)), vaultBefore, "vault must not change");
    }

    // =========================================================================
    // FUZZ TEST 4: DELAY NEVER WITHDRAWS CAPITAL
    // =========================================================================

    function testFuzz_DelayNeverWithdraws(uint256 recommendedDelay) public {
        recommendedDelay = bound(recommendedDelay, 0, 365 days);

        uint256 vaultBefore = usdc.balanceOf(address(vault));

        IDecisionEngine.DecisionResult memory decision =
            _buildDecisionWithDelay(IDecisionEngine.DecisionAction.DELAY, 0, recommendedDelay);

        vm.prank(alice);
        IExecutionManager.ExecutionResult memory result = manager.executeDecision(strategyId, decision, 0, 0);

        assertEq(result.withdrawnAmount, 0, "DELAY must not withdraw");
        assertEq(result.executedAmount, 0, "DELAY must not execute");
        assertEq(usdc.balanceOf(address(vault)), vaultBefore, "vault balance unchanged");
    }

    // =========================================================================
    // TEST: ACCOUNTING ACCUMULATES CORRECTLY OVER MULTIPLE EXECUTIONS
    // =========================================================================

    function test_AccountingAccumulatesCorrectly() public {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1_000e6;
        amounts[1] = 2_000e6;
        amounts[2] = 3_000e6;
        amounts[3] = 4_000e6;

        uint256 totalExpected = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalExpected += amounts[i];
            IDecisionEngine.DecisionResult memory d =
                _buildDecision(IDecisionEngine.DecisionAction.PARTIAL_EXECUTION, amounts[i]);

            vm.prank(alice);
            manager.executeDecision(strategyId, d, i, 0);

            IExecutionManager.ExecutionRecord memory record = manager.getExecutionRecord(strategyId);
            assertEq(record.totalExecuted, totalExpected);
            assertEq(record.executionCount, i + 1);
            assertEq(record.lastExecutionAmount, amounts[i]);
            assertEq(record.nonce, i + 1);
        }

        assertEq(manager.getRemainingAllocation(strategyId), 0);
    }

    // =========================================================================
    // TEST: SWAP WITH MIN OUTPUT SLIPPAGE CHECK
    // =========================================================================

    function test_RevertSwapBelowMinOutput() public {
        // Set rate to produce less output
        swapExecutor.setMockExchangeRate(0.5e6); // 0.5:1

        IDecisionEngine.DecisionResult memory decision = _buildDecision(IDecisionEngine.DecisionAction.EXECUTE, 1_000e6);

        // Require 1000 output, but only 500 will be produced
        vm.prank(alice);
        vm.expectRevert(); // InsufficientOutputAmount
        manager.executeDecision(strategyId, decision, 0, 1_000e6);
    }

    // =========================================================================
    // TEST: OWNER IS ALWAYS AUTHORIZED EXECUTOR
    // =========================================================================

    function test_OwnerIsAlwaysAuthorized() public view {
        assertTrue(manager.isAuthorizedExecutor(strategyId, alice));
    }

    // =========================================================================
    // TEST: INITIAL EXECUTION RECORD IS ZEROED
    // =========================================================================

    function test_InitialExecutionRecordZeroed() public view {
        IExecutionManager.ExecutionRecord memory record = manager.getExecutionRecord(strategyId);
        assertEq(record.totalExecuted, 0);
        assertEq(record.lastExecutionTimestamp, 0);
        assertEq(record.lastExecutionAmount, 0);
        assertEq(record.executionCount, 0);
        assertEq(record.nonce, 0);
    }
}
