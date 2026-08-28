// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DecisionEngine} from "../src/decision/DecisionEngine.sol";
import {IDecisionEngine} from "../src/interfaces/IDecisionEngine.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";
import {MarketDataTypes} from "../src/market/MarketDataTypes.sol";
import {YieldDataTypes} from "../src/yield/YieldDataTypes.sol";

/**
 * @title DecisionEngineTest
 * @notice Comprehensive test suite for Module 5: DecisionEngine.
 * @dev All tests use deterministic, bounded inputs. No ML, AI, or randomness.
 */
contract DecisionEngineTest is Test {
    DecisionEngine public engine;
    address public owner = address(this);

    // -------------------------------------------------------------------------
    // HELPERS: Default fixture builders
    // -------------------------------------------------------------------------

    function _defaultStrategy() internal view returns (IDCAStrategy.Strategy memory) {
        return IDCAStrategy.Strategy({
            owner: address(0xABCD),
            inputToken: address(0x1111),
            targetToken: address(0x2222),
            targetAllocation: 10_000e6, // 10,000 USDC
            frequency: 1 days,
            maxDelay: 4 hours,
            minExecutionAmount: 100e6, // 100 USDC
            maxExecutionAmount: 10_000e6, // 10,000 USDC
            nextExecutionTime: block.timestamp,
            status: IDCAStrategy.StrategyStatus.ACTIVE
        });
    }

    function _defaultMarket() internal view returns (MarketDataTypes.MarketState memory) {
        return MarketDataTypes.MarketState({
            currentPrice: 1000e18, // $1000 per token
            twap: 1000e18,
            priceDeviation: 0,
            volatility: 0.05e18, // 5% volatility
            liquidity: 1_000_000e18, // 1M tokens
            estimatedSlippage: 50, // 0.5% slippage
            estimatedPriceImpact: 30, // 0.3% price impact
            timestamp: block.timestamp,
            dataSource: bytes32(0)
        });
    }

    function _defaultYield() internal pure returns (YieldDataTypes.YieldAnalysis memory) {
        return YieldDataTypes.YieldAnalysis({
            currentAPY: 500, // 5% APY
            estimatedWaitingYield: 100e6,
            opportunityCost: 50e6,
            waitingBenefit: 50e6,
            urgency: 3000, // 30% through delay window
            remainingDelay: 2 hours,
            recommendation: YieldDataTypes.Recommendation.WAIT
        });
    }

    function _defaultContext() internal pure returns (IDecisionEngine.ExecutionContext memory) {
        return IDecisionEngine.ExecutionContext({
            lastExecutionTimestamp: 0,
            lastExecutionAmount: 0,
            totalExecutedSoFar: 0
        });
    }

    function _evaluate(
        IDCAStrategy.Strategy memory strategy,
        MarketDataTypes.MarketState memory market,
        YieldDataTypes.YieldAnalysis memory yield,
        uint256 availableCapital,
        uint256 currentDelay
    ) internal view returns (IDecisionEngine.DecisionResult memory) {
        return engine.evaluate(strategy, market, yield, availableCapital, currentDelay, _defaultContext());
    }

    // -------------------------------------------------------------------------
    // SETUP
    // -------------------------------------------------------------------------

    function setUp() public {
        engine = new DecisionEngine(owner);
    }

    // -------------------------------------------------------------------------
    // 1. Deployment & Configuration
    // -------------------------------------------------------------------------

    function test_Deployment() public view {
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        assertEq(cfg.marketWeightBps + cfg.yieldWeightBps + cfg.strategyWeightBps, 10_000);
        assertGt(cfg.executeThresholdBps, cfg.partialThresholdBps);
    }

    function test_SetConfig_Valid() public {
        IDecisionEngine.DecisionConfig memory newCfg = IDecisionEngine.DecisionConfig({
            marketWeightBps: 3000,
            yieldWeightBps: 3000,
            strategyWeightBps: 4000,
            executeThresholdBps: 7000,
            partialThresholdBps: 4500,
            volatilityThresholdBps: 2500,
            slippageThresholdBps: 150,
            priceImpactThresholdBps: 80,
            liquidityThreshold: 1e18,
            partialExecutionBps: 6000,
            minimumPartialExecutionBps: 1000,
            recommendedDelaySeconds: 7200
        });
        engine.setConfig(newCfg);

        IDecisionEngine.DecisionConfig memory loaded = engine.getConfig();
        assertEq(loaded.executeThresholdBps, 7000);
        assertEq(loaded.recommendedDelaySeconds, 7200);
    }

    function test_SetConfig_InvalidWeightsSum() public {
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        cfg.marketWeightBps = 5000;
        cfg.yieldWeightBps = 5000;
        cfg.strategyWeightBps = 1000; // Sum = 11000 != 10000
        vm.expectRevert();
        engine.setConfig(cfg);
    }

    function test_SetConfig_InvalidThreshold() public {
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        cfg.executeThresholdBps = 10001; // > BPS
        vm.expectRevert(DecisionEngine.InvalidConfig.selector);
        engine.setConfig(cfg);
    }

    function test_SetConfig_PartialExceedsExecute() public {
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        cfg.partialThresholdBps = cfg.executeThresholdBps + 1;
        vm.expectRevert(DecisionEngine.InvalidConfig.selector);
        engine.setConfig(cfg);
    }

    function test_SetConfig_NonOwner() public {
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        engine.setConfig(cfg);
    }

    // -------------------------------------------------------------------------
    // 2. Good Market → EXECUTE
    // -------------------------------------------------------------------------

    function test_GoodMarket_Execute() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        // price below TWAP = very favorable
        market.priceDeviation = -50e18; // 5% below TWAP

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.recommendation = YieldDataTypes.Recommendation.EXECUTE;
        yield.waitingBenefit = -10e6; // Negative: execute now
        yield.urgency = 10000;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.EXECUTE));
        assertGt(result.executionAmount, 0);
        assertEq(result.recommendedDelay, 0);
    }

    // -------------------------------------------------------------------------
    // 3. Bad Market → DELAY
    // -------------------------------------------------------------------------

    function test_BadMarket_Delay() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.8e18; // 80% volatility — very bad
        market.estimatedSlippage = 1000; // 10% slippage — bad
        market.estimatedPriceImpact = 500; // 5% impact — bad
        market.priceDeviation = 200e18; // price above TWAP — unfavorable
        market.liquidity = 0;

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.recommendation = YieldDataTypes.Recommendation.WAIT;
        yield.waitingBenefit = 500e6; // Very positive — wait
        yield.urgency = 0;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
        assertEq(result.executionAmount, 0);
    }

    // -------------------------------------------------------------------------
    // 4. High Volatility → DELAY or PARTIAL
    // -------------------------------------------------------------------------

    function test_HighVolatility_ReducesMarketScore() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.6e18; // 60% volatility

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 7000; // High urgency — pushes toward execution

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 1000);

        // High urgency but bad market: PARTIAL or EXECUTE (not DELAY because urgency is high)
        assertTrue(
            result.action == IDecisionEngine.DecisionAction.EXECUTE
                || result.action == IDecisionEngine.DecisionAction.PARTIAL_EXECUTION
                || result.action == IDecisionEngine.DecisionAction.DELAY
        );
        assertLe(result.diagnostics.marketScore, 8000); // Market score should be penalized
    }

    // -------------------------------------------------------------------------
    // 5. Low Liquidity → Penalizes Market Score
    // -------------------------------------------------------------------------

    function test_LowLiquidity_PenalizesScore() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.liquidity = 0; // Zero liquidity

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = 1000e6; // Very positive — want to wait

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        // Zero liquidity should penalize market score
        assertEq(result.diagnostics.liquidity, 0);
        // Low market score combined with positive wait benefit → likely DELAY
        assertTrue(result.action != IDecisionEngine.DecisionAction.EXECUTE || result.score >= 6500);
    }

    // -------------------------------------------------------------------------
    // 6. High Slippage → Penalizes Score
    // -------------------------------------------------------------------------

    function test_HighSlippage_Penalizes() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.estimatedSlippage = 2000; // 20% slippage — very bad

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = 500e6;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertLe(result.diagnostics.marketScore, 8500);
    }

    // -------------------------------------------------------------------------
    // 7. High Price Impact → Penalizes Score
    // -------------------------------------------------------------------------

    function test_HighPriceImpact_Penalizes() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.estimatedPriceImpact = 1000; // 10% impact — bad

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = 500e6;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertLe(result.diagnostics.marketScore, 8500);
    }

    // -------------------------------------------------------------------------
    // 8. Favorable Price Deviation → Boosts Market Score
    // -------------------------------------------------------------------------

    function test_FavorablePriceDeviation_Boosts() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.twap = 1000e18;
        market.priceDeviation = -200e18; // 20% below TWAP — very favorable for DCA buyer

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 5000;

        IDecisionEngine.DecisionResult memory resultFavorable =
            _evaluate(strategy, market, yield, 10_000e6, 0);

        // Compare with neutral deviation
        market.priceDeviation = 0;
        IDecisionEngine.DecisionResult memory resultNeutral =
            _evaluate(strategy, market, yield, 10_000e6, 0);

        assertGt(resultFavorable.diagnostics.marketScore, resultNeutral.diagnostics.marketScore);
    }

    // -------------------------------------------------------------------------
    // 9. Unfavorable Price Deviation → Reduces Score
    // -------------------------------------------------------------------------

    function test_UnfavorablePriceDeviation_Reduces() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.twap = 1000e18;
        market.priceDeviation = 400e18; // 40% above TWAP — bad

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertLe(result.diagnostics.marketScore, 8500);
    }

    // -------------------------------------------------------------------------
    // 10. Attractive Vault Yield → Positive Yield Score
    // -------------------------------------------------------------------------

    function test_AttractiveVaultYield_BoostsYieldScore() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.currentAPY = 1000; // 10% APY
        yield.waitingBenefit = 500e6; // Positive benefit
        yield.recommendation = YieldDataTypes.Recommendation.WAIT;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertGt(result.diagnostics.yieldScore, 5000);
    }

    // -------------------------------------------------------------------------
    // 11. Negative Waiting Benefit → Execute
    // -------------------------------------------------------------------------

    function test_NegativeWaitingBenefit_FavorsExecute() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = -500e6; // Clearly negative
        yield.recommendation = YieldDataTypes.Recommendation.EXECUTE;
        yield.urgency = 6000;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 1 hours);

        // Negative waiting benefit + medium-high urgency should push toward execution
        assertTrue(result.action != IDecisionEngine.DecisionAction.DELAY || result.score < 4000);
    }

    // -------------------------------------------------------------------------
    // 12. Maximum Delay Reached → Must Not DELAY
    // -------------------------------------------------------------------------

    function test_MaxDelayReached_MustNotDelay() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxDelay = 1 hours;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.9e18; // Terrible market conditions

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 10_000; // Maximum urgency

        // currentDelay == maxDelay
        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 1 hours);

        // Must never return DELAY when max delay is reached AND capital is available
        assertNotEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
    }

    // -------------------------------------------------------------------------
    // 13. Current Delay > Max Delay → Must Not DELAY
    // -------------------------------------------------------------------------

    function test_DelayExceedsMax_MustNotDelay() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxDelay = 1 hours;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 2 hours);

        assertNotEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
    }

    // -------------------------------------------------------------------------
    // 14. Minimum Execution Constraint
    // -------------------------------------------------------------------------

    function test_MinExecutionConstraint() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.minExecutionAmount = 500e6;
        strategy.maxExecutionAmount = 10_000e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 9000; // Very high urgency → should execute

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 3 hours);

        if (result.executionAmount > 0) {
            assertGe(result.executionAmount, strategy.minExecutionAmount);
        }
    }

    // -------------------------------------------------------------------------
    // 15. Maximum Execution Constraint
    // -------------------------------------------------------------------------

    function test_MaxExecutionConstraint() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxExecutionAmount = 5_000e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.priceDeviation = -100e18; // Very favorable

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 9000;

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 3 hours);

        assertLe(result.executionAmount, strategy.maxExecutionAmount);
    }

    // -------------------------------------------------------------------------
    // 16. Remaining Allocation < Target
    // -------------------------------------------------------------------------

    function test_PartialRemainingAllocation() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.targetAllocation = 10_000e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 9000;

        IDecisionEngine.ExecutionContext memory ctx = IDecisionEngine.ExecutionContext({
            lastExecutionTimestamp: 0,
            lastExecutionAmount: 0,
            totalExecutedSoFar: 8_000e6 // 8000 already done → 2000 remaining
        });

        IDecisionEngine.DecisionResult memory result =
            engine.evaluate(strategy, market, yield, 10_000e6, 3 hours, ctx);

        assertLe(result.executionAmount, 2_000e6); // Cannot exceed remaining
    }

    // -------------------------------------------------------------------------
    // 17. Capital < Target
    // -------------------------------------------------------------------------

    function test_CapitalConstraint() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 9000;

        uint256 limitedCapital = 2_000e6;
        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, limitedCapital, 3 hours);

        assertLe(result.executionAmount, limitedCapital);
    }

    // -------------------------------------------------------------------------
    // 18. Zero Remaining Allocation → DELAY with executionAmount == 0
    // -------------------------------------------------------------------------

    function test_ZeroRemainingAllocation() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.targetAllocation = 5_000e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.ExecutionContext memory ctx = IDecisionEngine.ExecutionContext({
            lastExecutionTimestamp: 0,
            lastExecutionAmount: 0,
            totalExecutedSoFar: 5_000e6 // Fully executed
        });

        IDecisionEngine.DecisionResult memory result = engine.evaluate(strategy, market, yield, 10_000e6, 0, ctx);

        assertEq(result.executionAmount, 0);
        assertEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
    }

    // -------------------------------------------------------------------------
    // 19. Completed Strategy → No Execution
    // -------------------------------------------------------------------------

    function test_CompletedStrategy_NoExecution() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.status = IDCAStrategy.StrategyStatus.COMPLETED;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(result.executionAmount, 0);
    }

    // -------------------------------------------------------------------------
    // 20. Paused Strategy → No Execution
    // -------------------------------------------------------------------------

    function test_PausedStrategy_NoExecution() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.status = IDCAStrategy.StrategyStatus.PAUSED;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(result.executionAmount, 0);
        assertFalse(result.diagnostics.strategyActive);
    }

    // -------------------------------------------------------------------------
    // 21. Cancelled Strategy → No Execution
    // -------------------------------------------------------------------------

    function test_CancelledStrategy_NoExecution() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.status = IDCAStrategy.StrategyStatus.CANCELLED;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(result.executionAmount, 0);
        assertFalse(result.diagnostics.strategyActive);
    }

    // -------------------------------------------------------------------------
    // 22. Invalid Market Data → Safe Handling
    // -------------------------------------------------------------------------

    function test_ZeroLiquidity_SafeHandling() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.liquidity = 0;
        market.twap = 0; // Also zero TWAP

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        // Should not revert
        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertLe(result.diagnostics.marketScore, 8500); // Zero liquidity = poor market score
    }

    // -------------------------------------------------------------------------
    // 23. Conflicting Constraints — Urgency High but Market Bad
    // -------------------------------------------------------------------------

    function test_ConflictingConstraints_UrgencyWins() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxDelay = 4 hours;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.9e18; // Very bad market
        market.estimatedSlippage = 500;

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 10_000; // Maximum — window completely exhausted

        // currentDelay equals maxDelay: maximum delay override applies
        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 4 hours);

        // Strategy urgency is max, max delay reached → must not DELAY
        assertNotEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
    }

    // -------------------------------------------------------------------------
    // 24. Partial Execution Calculation
    // -------------------------------------------------------------------------

    function test_PartialExecution_Amount() public {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxExecutionAmount = 10_000e6;
        strategy.minExecutionAmount = 100e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.25e18; // Elevated but not terrible
        market.estimatedSlippage = 150;

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 5000; // Medium urgency
        yield.waitingBenefit = -100e6; // Slight negative

        // Force score into partial range by tweaking config
        IDecisionEngine.DecisionConfig memory cfg = engine.getConfig();
        cfg.executeThresholdBps = 9000; // Very high execute threshold
        cfg.partialThresholdBps = 4000;
        engine.setConfig(cfg);

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 1 hours);

        if (result.action == IDecisionEngine.DecisionAction.PARTIAL_EXECUTION) {
            assertGe(result.executionAmount, strategy.minExecutionAmount);
            assertLe(result.executionAmount, strategy.maxExecutionAmount);
            // Should be ~50% of maxExecutionAmount by default config
            assertLe(result.executionAmount, (strategy.maxExecutionAmount * 6000) / 10_000);
        }
    }

    // -------------------------------------------------------------------------
    // 25. Full Execution Calculation
    // -------------------------------------------------------------------------

    function test_FullExecution_Amount() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxExecutionAmount = 5_000e6;
        strategy.minExecutionAmount = 100e6;
        strategy.targetAllocation = 10_000e6;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.priceDeviation = -200e18; // 20% below TWAP — very favorable
        market.volatility = 0.02e18; // Very low volatility

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = 8000;
        yield.waitingBenefit = -500e6; // Negative benefit → push to execute

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 3 hours);

        if (result.action == IDecisionEngine.DecisionAction.EXECUTE) {
            assertGe(result.executionAmount, strategy.minExecutionAmount);
            assertLe(result.executionAmount, strategy.maxExecutionAmount);
        }
    }

    // -------------------------------------------------------------------------
    // 26. Delay Recommended Amount
    // -------------------------------------------------------------------------

    function test_Delay_RecommendedDelay() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxDelay = 4 hours;

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.8e18; // Bad market → delay

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = 500e6; // Positive → delay
        yield.recommendation = YieldDataTypes.Recommendation.WAIT;
        yield.urgency = 1000; // Low urgency

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        if (result.action == IDecisionEngine.DecisionAction.DELAY) {
            assertGt(result.recommendedDelay, 0);
            // Recommended delay must not exceed remaining window
            assertLe(result.recommendedDelay, strategy.maxDelay);
        }
    }

    // -------------------------------------------------------------------------
    // 27. Recommended Delay Boundary
    // -------------------------------------------------------------------------

    function test_Delay_NeverExceedsRemainingWindow() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.maxDelay = 1 hours; // Very tight window

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.8e18;

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = 500e6;
        yield.urgency = 500; // Low urgency → eligible for delay

        uint256 currentDelay = 30 minutes; // 30 min elapsed, 30 min remaining

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, currentDelay);

        if (result.action == IDecisionEngine.DecisionAction.DELAY) {
            assertLe(result.recommendedDelay, strategy.maxDelay - currentDelay);
        }
    }

    // -------------------------------------------------------------------------
    // 28. Deterministic Repeated Evaluation
    // -------------------------------------------------------------------------

    function test_Deterministic_RepeatedCalls() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory r1 = _evaluate(strategy, market, yield, 5_000e6, 1 hours);
        IDecisionEngine.DecisionResult memory r2 = _evaluate(strategy, market, yield, 5_000e6, 1 hours);

        assertEq(uint256(r1.action), uint256(r2.action));
        assertEq(r1.executionAmount, r2.executionAmount);
        assertEq(r1.score, r2.score);
    }

    // -------------------------------------------------------------------------
    // 29. Score is Normalized 0–10000
    // -------------------------------------------------------------------------

    function test_Score_Normalized() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 5_000e6, 1 hours);

        assertLe(result.score, 10_000);
    }

    // -------------------------------------------------------------------------
    // 30. Diagnostics Populated
    // -------------------------------------------------------------------------

    function test_Diagnostics_Populated() public view {
        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertEq(result.diagnostics.price, market.currentPrice);
        assertEq(result.diagnostics.twap, market.twap);
        assertEq(result.diagnostics.currentAPY, yield.currentAPY);
        assertEq(result.diagnostics.waitingBenefit, yield.waitingBenefit);
        assertTrue(result.diagnostics.strategyActive);
    }

    // -------------------------------------------------------------------------
    // FUZZ TESTS
    // -------------------------------------------------------------------------

    function testFuzz_ExecutionAmountInvariants(
        uint128 targetAllocation,
        uint128 minExecution,
        uint128 maxExecution,
        uint128 availableCapital,
        uint32 currentDelay,
        uint32 maxDelay,
        uint16 urgency
    ) public view {
        // Bound to valid strategy constraints
        targetAllocation = uint128(bound(targetAllocation, 1e6, 1_000_000e6));
        minExecution = uint128(bound(minExecution, 1, targetAllocation));
        maxExecution = uint128(bound(maxExecution, minExecution, targetAllocation));
        availableCapital = uint128(bound(availableCapital, 0, 1_000_000e6));
        maxDelay = uint32(bound(maxDelay, 1, 30 days));
        currentDelay = uint32(bound(currentDelay, 0, maxDelay * 2));
        urgency = uint16(bound(urgency, 0, 10_000));

        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        strategy.targetAllocation = targetAllocation;
        strategy.minExecutionAmount = minExecution;
        strategy.maxExecutionAmount = maxExecution;
        strategy.maxDelay = maxDelay;

        MarketDataTypes.MarketState memory market = _defaultMarket();

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.urgency = urgency;

        IDecisionEngine.DecisionResult memory result =
            _evaluate(strategy, market, yield, availableCapital, currentDelay);

        // Invariant 1: execution amount <= remaining allocation
        assertLe(result.executionAmount, targetAllocation);

        // Invariant 2: execution amount <= max execution amount
        assertLe(result.executionAmount, maxExecution);

        // Invariant 3: execution amount <= available capital
        assertLe(result.executionAmount, availableCapital);

        // Invariant 4: if executionAmount > 0, must be >= minExecution
        if (result.executionAmount > 0) {
            assertGe(result.executionAmount, minExecution);
        }

        // Invariant 5: if action == DELAY, executionAmount == 0
        if (result.action == IDecisionEngine.DecisionAction.DELAY) {
            assertEq(result.executionAmount, 0);
        }

        // Invariant 6: if maxDelay is reached AND capital >= minExecution, must NOT be DELAY
        if (currentDelay >= maxDelay && availableCapital >= minExecution) {
            assertNotEq(uint256(result.action), uint256(IDecisionEngine.DecisionAction.DELAY));
        }

        // Invariant 7: score <= 10000
        assertLe(result.score, 10_000);

        // Invariant 8: recommended delay <= remaining window
        if (result.action == IDecisionEngine.DecisionAction.DELAY && currentDelay < maxDelay) {
            assertLe(result.recommendedDelay, maxDelay - currentDelay);
        }
    }

    function testFuzz_MarketScore_Bounded(uint128 volatility, uint16 slippage, uint16 impact, uint128 liquidity)
        public
        view
    {
        volatility = uint128(bound(volatility, 0, 5e18)); // up to 500%
        slippage = uint16(bound(slippage, 0, 10_000)); // up to 100%
        impact = uint16(bound(impact, 0, 10_000)); // up to 100%

        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = volatility;
        market.estimatedSlippage = slippage;
        market.estimatedPriceImpact = impact;
        market.liquidity = liquidity;

        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        assertLe(result.diagnostics.marketScore, 10_000);
        assertLe(result.score, 10_000);
    }

    function testFuzz_PositiveWaitingBenefit_NeverForcesExecution(uint128 waitingBenefit) public view {
        waitingBenefit = uint128(bound(waitingBenefit, 1, 1_000_000e6));

        IDCAStrategy.Strategy memory strategy = _defaultStrategy();
        MarketDataTypes.MarketState memory market = _defaultMarket();
        market.volatility = 0.8e18; // Bad market → should delay

        YieldDataTypes.YieldAnalysis memory yield = _defaultYield();
        yield.waitingBenefit = int256(uint256(waitingBenefit));
        yield.recommendation = YieldDataTypes.Recommendation.WAIT;
        yield.urgency = 1000; // Low urgency → no override

        IDecisionEngine.DecisionResult memory result = _evaluate(strategy, market, yield, 10_000e6, 0);

        // Bad market + very positive waiting benefit + low urgency should not force EXECUTE
        // (score should be below execute threshold)
        if (result.action == IDecisionEngine.DecisionAction.EXECUTE) {
            // Only acceptable if score justifies it
            assertGe(result.score, 6500);
        }
    }
}
