// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DCAEngine} from "../../src/DCAEngine.sol";
import {YieldVault} from "../../src/YieldVault.sol";
import {ExecutionManager} from "../../src/execution/ExecutionManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockSwapExecutor} from "../../src/mocks/MockSwapExecutor.sol";
import {MarketAnalyzer} from "../../src/market/MarketAnalyzer.sol";
import {MockMarketDataProvider} from "../../src/market/MockMarketDataProvider.sol";
import {YieldAnalyzer} from "../../src/yield/YieldAnalyzer.sol";
import {DecisionEngine} from "../../src/decision/DecisionEngine.sol";

import {IDCAStrategy} from "../../src/interfaces/IDCAStrategy.sol";
import {IExecutionManager} from "../../src/interfaces/IExecutionManager.sol";
import {MarketDataTypes} from "../../src/market/MarketDataTypes.sol";
import {YieldDataTypes} from "../../src/yield/YieldDataTypes.sol";
import {IDecisionEngine} from "../../src/interfaces/IDecisionEngine.sol";

/**
 * @title EndToEndDCAIntegrationTest
 * @notice Module 12: End-to-End Integration Test Suite.
 */
contract EndToEndDCAIntegrationTest is Test {
    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------
    MockERC20 public usdc;
    MockERC20 public weth;
    DCAEngine public dcaEngine;
    YieldVault public vault;
    MarketAnalyzer public marketAnalyzer;
    MockMarketDataProvider public marketProvider;
    YieldAnalyzer public yieldAnalyzer;
    DecisionEngine public decisionEngine;
    ExecutionManager public executionManager;
    MockSwapExecutor public mockExecutor;

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    uint256 public strategyId;

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------
    uint256 constant INITIAL_USDC = 100_000e6; // 100,000 USDC
    uint256 constant TARGET_ALLOCATION = 10_000e6; // 10,000 USDC
    uint256 constant MIN_EXECUTION = 100e6; // 100 USDC
    uint256 constant MAX_EXECUTION = 10_000e6; // 10,000 USDC
    uint256 constant FREQUENCY = 1 days;
    uint256 constant MAX_DELAY = 5 days;

    // -------------------------------------------------------------------------
    // SETUP
    // -------------------------------------------------------------------------
    function setUp() public {
        vm.warp(1000 days);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        dcaEngine = new DCAEngine();
        vault = new YieldVault(IERC20(address(usdc)), "Vault", "vUSDC", deployer);

        marketProvider = new MockMarketDataProvider();
        marketAnalyzer = new MarketAnalyzer(address(marketProvider));

        yieldAnalyzer = new YieldAnalyzer(address(vault), deployer);
        decisionEngine = new DecisionEngine(deployer);

        // Use MockSwapExecutor to test ExecutionManager logic deterministically without Uniswap v4 complexities
        mockExecutor = new MockSwapExecutor(address(weth), 1e6);

        executionManager = new ExecutionManager(deployer, address(dcaEngine), address(vault), address(mockExecutor));
        vault.setAuthorizedOperator(address(executionManager), true);

        usdc.mint(alice, INITIAL_USDC);
        weth.mint(address(mockExecutor), 10_000e18);
    }

    // -------------------------------------------------------------------------
    // E2E SCENARIO
    // -------------------------------------------------------------------------
    function _createStrategyAndAuthorize(uint256 depositAmount) internal {
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);

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
        executionManager.setStrategyExecutor(strategyId, address(this), true);
        vm.stopPrank();
    }

    function test_E2E_DayByDay() public {
        // --- SETUP STRATEGY ---
        _createStrategyAndAuthorize(INITIAL_USDC);

        // --- DAY 0: DELAY ---
        _setMarketConditions(false); // POOR
        vault.setSimulatedAPY(500);

        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();
        assertEq(uint256(decision.action), uint256(IDecisionEngine.DecisionAction.DELAY), "Day 0 should DELAY");

        // --- DAY 1: DELAY ---
        vm.warp(block.timestamp + 1 days);
        decision = _evaluateStrategy();
        assertEq(uint256(decision.action), uint256(IDecisionEngine.DecisionAction.DELAY), "Day 1 should DELAY");

        // --- DAY 2: EXECUTION ---
        vm.warp(block.timestamp + 1 days);
        _setMarketConditions(true); // IMPROVED

        decision = _evaluateStrategy();

        assertTrue(
            decision.action == IDecisionEngine.DecisionAction.PARTIAL_EXECUTION
                || decision.action == IDecisionEngine.DecisionAction.EXECUTE,
            "Day 2 should EXECUTE or PARTIAL"
        );

        uint256 expectedRemaining = TARGET_ALLOCATION - decision.executionAmount;
        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);

        executionManager.executeDecision(strategyId, decision, record.nonce, 0);

        uint256 remaining = executionManager.getRemainingAllocation(strategyId);
        assertEq(remaining, expectedRemaining, "Remaining allocation mismatch");

        IExecutionManager.ExecutionRecord memory finalRecord = executionManager.getExecutionRecord(strategyId);
        assertEq(finalRecord.totalExecuted, decision.executionAmount, "Total executed mismatch");
        assertEq(finalRecord.executionCount, 1, "Execution count should be 1");
        assertEq(finalRecord.nonce, record.nonce + 1, "Nonce should increment");
    }

    function test_E2E_FailedSwap_RollsBack() public {
        _createStrategyAndAuthorize(INITIAL_USDC);

        _setMarketConditions(true);
        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();
        decision.action = IDecisionEngine.DecisionAction.EXECUTE;
        decision.executionAmount = TARGET_ALLOCATION;

        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);
        mockExecutor.setShouldFail(true);

        uint256 preVaultAssets = vault.totalAssets();

        vm.expectRevert();
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);

        assertEq(vault.totalAssets(), preVaultAssets, "Vault assets should be unchanged");

        IExecutionManager.ExecutionRecord memory postRecord = executionManager.getExecutionRecord(strategyId);
        assertEq(postRecord.totalExecuted, 0, "No execution should be recorded");
        assertEq(postRecord.nonce, record.nonce, "Nonce should not increment");
    }

    function test_E2E_RepeatedExecution_Reverts() public {
        _createStrategyAndAuthorize(INITIAL_USDC);

        _setMarketConditions(true);
        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();
        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);

        // First execution succeeds
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);

        // Second execution with same nonce must revert
        vm.expectRevert();
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);
    }

    function test_E2E_MaximumDelay() public {
        _createStrategyAndAuthorize(INITIAL_USDC);

        _setMarketConditions(false); // POOR conditions

        // Warp PAST max delay
        vm.warp(block.timestamp + MAX_DELAY + 1 hours);

        // Urgency will be 10,000 bps (100%), forcing an EXECUTE regardless of conditions
        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();

        assertEq(
            uint256(decision.action), uint256(IDecisionEngine.DecisionAction.EXECUTE), "Max delay should force EXECUTE"
        );

        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);
        assertEq(executionManager.getRemainingAllocation(strategyId), 0, "Should have executed full amount");
    }

    function test_E2E_InsufficientCapital() public {
        _createStrategyAndAuthorize(1000e6); // Small deposit

        _setMarketConditions(true);
        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();

        // Manually try to force full execution which needs TARGET_ALLOCATION
        decision.action = IDecisionEngine.DecisionAction.EXECUTE;
        decision.executionAmount = TARGET_ALLOCATION;

        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);

        vm.expectRevert();
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);
    }

    function test_E2E_PausedStrategy() public {
        _createStrategyAndAuthorize(INITIAL_USDC);

        vm.startPrank(alice);
        dcaEngine.pauseStrategy(strategyId);
        vm.stopPrank();

        _setMarketConditions(true);
        IDecisionEngine.DecisionResult memory decision = _evaluateStrategy();

        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);

        // ExecutionManager validate/execute will revert for paused strategies
        vm.expectRevert();
        executionManager.executeDecision(strategyId, decision, record.nonce, 0);
    }

    function test_E2E_InvalidStrategy() public {
        IDecisionEngine.DecisionResult memory decision = IDecisionEngine.DecisionResult({
            action: IDecisionEngine.DecisionAction.EXECUTE,
            targetAmount: TARGET_ALLOCATION,
            executionAmount: TARGET_ALLOCATION,
            remainingAmount: 0,
            recommendedDelay: 0,
            score: 8000,
            reason: "Mock EXECUTE",
            timestamp: block.timestamp,
            diagnostics: _emptyDiagnostics()
        });

        vm.expectRevert();
        executionManager.executeDecision(999, decision, 0, 0);
    }

    // -------------------------------------------------------------------------
    // HELPERS
    // -------------------------------------------------------------------------
    function _evaluateStrategy() internal view returns (IDecisionEngine.DecisionResult memory) {
        IDCAStrategy.Strategy memory strategy = dcaEngine.getStrategy(strategyId);
        MarketDataTypes.MarketState memory market = marketAnalyzer.getMarketState();
        uint256 capital = vault.getUserAssets(alice);
        uint256 currentDelay =
            block.timestamp > strategy.nextExecutionTime ? block.timestamp - strategy.nextExecutionTime : 0;
        YieldDataTypes.YieldAnalysis memory yield =
            yieldAnalyzer.analyzeYieldOpportunity(capital, market, currentDelay, strategy.maxDelay);

        IExecutionManager.ExecutionRecord memory record = executionManager.getExecutionRecord(strategyId);
        IDecisionEngine.ExecutionContext memory ctx = IDecisionEngine.ExecutionContext({
            lastExecutionTimestamp: record.lastExecutionTimestamp,
            lastExecutionAmount: record.lastExecutionAmount,
            totalExecutedSoFar: record.totalExecuted
        });

        return decisionEngine.evaluate(strategy, market, yield, capital, currentDelay, ctx);
    }

    function _setMarketConditions(bool improved) internal {
        if (improved) {
            marketProvider.setRawData(
                MarketDataTypes.RawMarketData({
                    currentPrice: 3000e18,
                    twap: 3000e18,
                    volatility: 0.05e18,
                    liquidity: 10_000_000e6,
                    dataSource: bytes32(0),
                    timestamp: block.timestamp
                })
            );
        } else {
            marketProvider.setRawData(
                MarketDataTypes.RawMarketData({
                    currentPrice: 4000e18,
                    twap: 3000e18,
                    volatility: 0.5e18,
                    liquidity: 100_000e6,
                    dataSource: bytes32(0),
                    timestamp: block.timestamp
                })
            );
        }
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
}
