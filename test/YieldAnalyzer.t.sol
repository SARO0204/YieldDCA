// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldAnalyzer} from "../src/yield/YieldAnalyzer.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {YieldDataTypes} from "../src/yield/YieldDataTypes.sol";
import {MarketDataTypes} from "../src/market/MarketDataTypes.sol";

contract YieldAnalyzerTest is Test {
    YieldAnalyzer public analyzer;
    YieldVault public vault;
    MockERC20 public mockToken;

    address public user = address(0x123);
    address public owner = address(this);
    uint256 public constant INITIAL_DEPOSIT = 10_000e6; // 10,000 USDC

    function setUp() public {
        mockToken = new MockERC20("Mock USDC", "USDC", 6);
        vault = new YieldVault(mockToken, "Vault", "vUSDC", owner);
        analyzer = new YieldAnalyzer(address(vault), owner);

        // Setup user funds
        mockToken.mint(user, INITIAL_DEPOSIT);
        vm.startPrank(user);
        mockToken.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT, user);
        vm.stopPrank();
    }

    // ==========================================
    // A. Existing Functionality
    // ==========================================

    function test_RevertInvalidVault() public {
        vm.expectRevert(YieldAnalyzer.InvalidVault.selector);
        new YieldAnalyzer(address(0), owner);
    }

    function test_GetYieldStateForAmount() public {
        vault.setSimulatedAPY(500); // 5%

        uint256 amount = 1_000e6;
        YieldDataTypes.YieldState memory state = analyzer.getYieldStateForAmount(amount);

        assertEq(state.currentAPY, 500);
        assertEq(state.principalAssets, 1_000e6);
        assertEq(state.projectedYield365D, 50e6);
        assertEq(state.projectedYield7D, (uint256(50e6) * 7 days) / 365 days);
        assertEq(state.projectedYield30D, (uint256(50e6) * 30 days) / 365 days);
    }

    function test_GetYieldStateForUser() public {
        vault.setSimulatedAPY(1000); // 10%
        YieldDataTypes.YieldState memory state = analyzer.getYieldStateForUser(user);

        assertEq(state.currentAPY, 1000);
        assertEq(state.principalAssets, 10_000e6);
        assertEq(state.projectedYield365D, 1_000e6);
        assertEq(state.projectedYield7D, (uint256(1_000e6) * 7 days) / 365 days);
        assertEq(state.projectedYield30D, (uint256(1_000e6) * 30 days) / 365 days);
    }

    // ==========================================
    // B. Yield Calculation & Setup Helpers
    // ==========================================

    function _getEmptyMarketState() internal pure returns (MarketDataTypes.MarketState memory) {
        return MarketDataTypes.MarketState({
            currentPrice: 1e18,
            twap: 1e18,
            priceDeviation: 0,
            volatility: 0,
            liquidity: 1000e18,
            estimatedSlippage: 0,
            estimatedPriceImpact: 0,
            timestamp: 1000,
            dataSource: bytes32(0)
        });
    }

    function test_analyzeYield_ZeroCapital() public {
        vault.setSimulatedAPY(500);
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(0, market, 0, 1000);

        assertEq(analysis.estimatedWaitingYield, 0);
        assertEq(analysis.opportunityCost, 0);
        assertEq(analysis.waitingBenefit, 0);
    }

    function test_analyzeYield_ZeroAPY() public {
        vault.setSimulatedAPY(0);
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);

        assertEq(analysis.estimatedWaitingYield, 0);
    }

    function test_analyzeYield_WaitingPeriods() public {
        vault.setSimulatedAPY(1000); // 10%
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();

        // Zero waiting period
        (uint256 wp, uint256 vw, uint256 dw, uint256 ut) = analyzer.config();
        analyzer.setAnalyzerConfig(
            YieldDataTypes.AnalyzerConfig({
                waitingPeriod: 0, volatilityWeightBps: vw, deviationWeightBps: dw, urgencyThresholdBps: ut
            })
        );

        YieldDataTypes.YieldAnalysis memory analysis0 = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);
        assertEq(analysis0.estimatedWaitingYield, 0);

        // 1 day waiting period
        analyzer.setAnalyzerConfig(
            YieldDataTypes.AnalyzerConfig({
                waitingPeriod: 1 days, volatilityWeightBps: vw, deviationWeightBps: dw, urgencyThresholdBps: ut
            })
        );
        YieldDataTypes.YieldAnalysis memory analysis1 = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);
        uint256 expectedYield = (uint256(1000e6) * 1000 * uint256(1 days)) / (10000 * uint256(365 days));
        assertEq(analysis1.estimatedWaitingYield, expectedYield);
    }

    // ==========================================
    // C. Opportunity Cost
    // ==========================================

    function test_OpportunityCost_VolatilityOnly() public {
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        market.volatility = 0.1e18; // 10% volatility -> 1000 BPS
        // Default volatility weight is 2000 BPS (20%)
        // Weighted Volatility = 1000 * 2000 / 10000 = 200 BPS
        // Opp Cost on 1000e6 = 1000e6 * 200 / 10000 = 20e6

        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);
        assertEq(analysis.opportunityCost, 20e6);
    }

    function test_OpportunityCost_DeviationOnly() public {
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        market.twap = 1000e18;
        market.priceDeviation = -100e18; // 10% deviation -> 1000 BPS

        // Default deviation weight is 3000 BPS (30%)
        // Weighted Deviation = 1000 * 3000 / 10000 = 300 BPS
        // Opp Cost on 1000e6 = 1000e6 * 300 / 10000 = 30e6

        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);
        assertEq(analysis.opportunityCost, 30e6);
    }

    function test_OpportunityCost_CappedAt10000() public {
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        market.volatility = 5e18; // 500% volatility
        market.twap = 1000e18;
        market.priceDeviation = 5000e18; // 500% deviation

        // Total risk will easily exceed 10000 BPS
        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);

        // Opp cost capped at principal (10000 BPS = 100%)
        assertEq(analysis.opportunityCost, 1000e6);
    }

    // ==========================================
    // D. Waiting Benefit & G. Recommendation
    // ==========================================

    function test_WaitingBenefit_Wait() public {
        // High APY, low risk
        vault.setSimulatedAPY(10000); // 100% APY
        (, uint256 vw, uint256 dw, uint256 ut) = analyzer.config();
        analyzer.setAnalyzerConfig(
            YieldDataTypes.AnalyzerConfig({
                waitingPeriod: 365 days, volatilityWeightBps: vw, deviationWeightBps: dw, urgencyThresholdBps: ut
            })
        );

        MarketDataTypes.MarketState memory market = _getEmptyMarketState(); // zero risk

        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);
        assertEq(analysis.estimatedWaitingYield, 1000e6);
        assertEq(analysis.opportunityCost, 0);
        assertEq(analysis.waitingBenefit, int256(uint256(1000e6)));
        assertEq(uint256(analysis.recommendation), uint256(YieldDataTypes.Recommendation.WAIT));
    }

    function test_WaitingBenefit_Execute_NegativeBenefit() public {
        // Low APY, high risk
        vault.setSimulatedAPY(100); // 1% APY
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();
        market.volatility = 1e18; // 100% vol -> large opp cost

        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);

        assert(analysis.waitingBenefit < 0);
        assertEq(uint256(analysis.recommendation), uint256(YieldDataTypes.Recommendation.EXECUTE));
    }

    function test_Recommendation_Neutral() public {
        vault.setSimulatedAPY(0); // 0 APY
        MarketDataTypes.MarketState memory market = _getEmptyMarketState(); // 0 risk

        // 0 yield - 0 cost = 0 benefit
        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 1000);

        assertEq(analysis.waitingBenefit, int256(0));
        assertEq(uint256(analysis.recommendation), uint256(YieldDataTypes.Recommendation.NEUTRAL));
    }

    // ==========================================
    // E. Urgency & F. Remaining Delay
    // ==========================================

    function test_Urgency_And_RemainingDelay() public {
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();

        // Normal case
        YieldDataTypes.YieldAnalysis memory a1 = analyzer.analyzeYieldOpportunity(1000e6, market, 250, 1000);
        assertEq(a1.urgency, 2500); // 25%
        assertEq(a1.remainingDelay, 750);

        // Max delay reached
        YieldDataTypes.YieldAnalysis memory a2 = analyzer.analyzeYieldOpportunity(1000e6, market, 1000, 1000);
        assertEq(a2.urgency, 10000);
        assertEq(a2.remainingDelay, 0);

        // Beyond max delay
        YieldDataTypes.YieldAnalysis memory a3 = analyzer.analyzeYieldOpportunity(1000e6, market, 2000, 1000);
        assertEq(a3.urgency, 10000);
        assertEq(a3.remainingDelay, 0);

        // Max delay is 0, current > 0
        YieldDataTypes.YieldAnalysis memory a4 = analyzer.analyzeYieldOpportunity(1000e6, market, 100, 0);
        assertEq(a4.urgency, 10000);
        assertEq(a4.remainingDelay, 0);

        // Max delay is 0, current == 0
        YieldDataTypes.YieldAnalysis memory a5 = analyzer.analyzeYieldOpportunity(1000e6, market, 0, 0);
        assertEq(a5.urgency, 0);
        assertEq(a5.remainingDelay, 0);
    }

    function test_Recommendation_Execute_Urgency() public {
        vault.setSimulatedAPY(10000); // Huge yield to make benefit positive
        MarketDataTypes.MarketState memory market = _getEmptyMarketState();

        // Even if benefit is positive, high urgency triggers EXECUTE
        YieldDataTypes.YieldAnalysis memory analysis = analyzer.analyzeYieldOpportunity(1000e6, market, 900, 1000); // 90% urgency > 80% threshold

        assert(analysis.waitingBenefit > 0);
        assertEq(analysis.urgency, 9000);
        assertEq(uint256(analysis.recommendation), uint256(YieldDataTypes.Recommendation.EXECUTE));
    }

    // ==========================================
    // H. Configuration
    // ==========================================

    function test_Config_Update() public {
        YieldDataTypes.AnalyzerConfig memory newConfig = YieldDataTypes.AnalyzerConfig({
            waitingPeriod: 7200, volatilityWeightBps: 1000, deviationWeightBps: 1000, urgencyThresholdBps: 9000
        });

        analyzer.setAnalyzerConfig(newConfig);
        (uint256 actualWp, uint256 actualVw, uint256 actualDw, uint256 actualUt) = analyzer.config();

        assertEq(actualWp, 7200);
        assertEq(actualVw, 1000);
        assertEq(actualDw, 1000);
        assertEq(actualUt, 9000);
    }

    function test_Config_InvalidWeights() public {
        (uint256 wp, uint256 vw, uint256 dw, uint256 ut) = analyzer.config();

        vm.expectRevert(YieldAnalyzer.InvalidConfig.selector);
        analyzer.setAnalyzerConfig(YieldDataTypes.AnalyzerConfig(wp, 10001, dw, ut));

        vm.expectRevert(YieldAnalyzer.InvalidConfig.selector);
        analyzer.setAnalyzerConfig(YieldDataTypes.AnalyzerConfig(wp, vw, 10001, ut));

        vm.expectRevert(YieldAnalyzer.InvalidConfig.selector);
        analyzer.setAnalyzerConfig(YieldDataTypes.AnalyzerConfig(wp, vw, dw, 10001));
    }

    function test_Config_NonOwner() public {
        (uint256 wp, uint256 vw, uint256 dw, uint256 ut) = analyzer.config();
        vm.prank(user);
        vm.expectRevert();
        analyzer.setAnalyzerConfig(YieldDataTypes.AnalyzerConfig(wp, vw, dw, ut));
    }

    // ==========================================
    // I. Fuzz Testing
    // ==========================================

    function testFuzz_AnalyzeOpportunity(
        uint256 principal,
        uint16 apyBps,
        uint32 waitingPeriod,
        uint64 volatility,
        int64 deviation,
        uint64 twap,
        uint32 currentDelay,
        uint32 maxDelay
    ) public {
        // Bound inputs to reasonable maximums to avoid overflow in multiplication before division
        principal = bound(principal, 0, 1_000_000_000e6); // Max 1B USDC
        apyBps = uint16(bound(apyBps, 0, 10000));
        twap = uint64(bound(twap, 1e18, 100_000e18)); // Avoid 0 TWAP

        vault.setSimulatedAPY(apyBps);

        MarketDataTypes.MarketState memory market = MarketDataTypes.MarketState({
            currentPrice: twap,
            twap: twap,
            priceDeviation: int256(deviation),
            volatility: uint256(volatility),
            liquidity: 1000e18,
            estimatedSlippage: 0,
            estimatedPriceImpact: 0,
            timestamp: 1000,
            dataSource: bytes32(0)
        });

        // Should not revert for any bounded valid values
        YieldDataTypes.YieldAnalysis memory analysis =
            analyzer.analyzeYieldOpportunity(principal, market, currentDelay, maxDelay);

        // Assert invariants
        assertTrue(analysis.urgency <= 10000);
        assertTrue(analysis.opportunityCost <= principal); // Cannot exceed 100% of principal

        if (maxDelay == 0) {
            assertTrue(analysis.remainingDelay == 0);
        }
    }
}
