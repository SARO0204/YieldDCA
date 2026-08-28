// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IYieldAnalyzer} from "../interfaces/IYieldAnalyzer.sol";
import {IYieldVault} from "../interfaces/IYieldVault.sol";
import {YieldDataTypes} from "./YieldDataTypes.sol";
import {MarketDataTypes} from "../market/MarketDataTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldAnalyzer
 * @notice Provides view-only normalization of yield projections and deterministic
 *         waiting-opportunity analysis based on the active YieldVault.
 * @dev Computations assume simple interest based on the simulated APY to provide deterministic projections
 *      for the Decision Engine. It depends exclusively on Module 2 (YieldVault).
 */
contract YieldAnalyzer is IYieldAnalyzer, Ownable {
    error InvalidVault();
    error InvalidConfig();

    IYieldVault public immutable vault;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant DAYS_7 = 7 days;
    uint256 private constant DAYS_30 = 30 days;
    uint256 private constant DAYS_365 = 365 days;
    uint256 private constant ONE_E18 = 1e18;

    YieldDataTypes.AnalyzerConfig public config;

    /**
     * @dev Initializes the analyzer with a YieldVault provider.
     * @param _vault Address of the Module 2 YieldVault contract.
     * @param initialOwner Address of the owner for configuration updates.
     */
    constructor(address _vault, address initialOwner) Ownable(initialOwner) {
        if (_vault == address(0)) revert InvalidVault();
        vault = IYieldVault(_vault);

        config = YieldDataTypes.AnalyzerConfig({
            waitingPeriod: 3600, // 1 hour waiting period assumed
            volatilityWeightBps: 2000, // 20% weight applied to volatility risk
            deviationWeightBps: 3000, // 30% weight applied to price deviation risk
            urgencyThresholdBps: 8000 // 80% delay consumption triggers EXECUTE
        });
    }

    /**
     * @notice Updates the analytical configuration assumptions.
     */
    function setAnalyzerConfig(YieldDataTypes.AnalyzerConfig calldata newConfig) external onlyOwner {
        if (newConfig.volatilityWeightBps > BPS_DENOMINATOR) revert InvalidConfig();
        if (newConfig.deviationWeightBps > BPS_DENOMINATOR) revert InvalidConfig();
        if (newConfig.urgencyThresholdBps > BPS_DENOMINATOR) revert InvalidConfig();
        config = newConfig;
    }

    /**
     * @inheritdoc IYieldAnalyzer
     */
    function getYieldStateForUser(address user) external view returns (YieldDataTypes.YieldState memory) {
        uint256 principal = vault.getUserAssets(user);
        return _computeState(principal);
    }

    /**
     * @inheritdoc IYieldAnalyzer
     */
    function getYieldStateForAmount(uint256 principalAmount) external view returns (YieldDataTypes.YieldState memory) {
        return _computeState(principalAmount);
    }

    /**
     * @notice Internal logic to calculate deterministic yield projections based on current APY.
     */
    function _computeState(uint256 principal) internal view returns (YieldDataTypes.YieldState memory) {
        // Fetch current APY from the vault
        uint256 currentAPY = vault.getCurrentAPY();

        // Projected Yield = (Principal * APY / 10000) * (Time / 365 days)
        uint256 yearlyYield = (principal * currentAPY) / BPS_DENOMINATOR;

        uint256 yield7D = (yearlyYield * DAYS_7) / DAYS_365;
        uint256 yield30D = (yearlyYield * DAYS_30) / DAYS_365;

        return YieldDataTypes.YieldState({
            currentAPY: currentAPY,
            principalAssets: principal,
            projectedYield7D: yield7D,
            projectedYield30D: yield30D,
            projectedYield365D: yearlyYield
        });
    }

    /**
     * @inheritdoc IYieldAnalyzer
     */
    function analyzeYieldOpportunity(
        uint256 principal,
        MarketDataTypes.MarketState memory marketState,
        uint256 currentDelay,
        uint256 maxDelay
    ) external view returns (YieldDataTypes.YieldAnalysis memory) {
        YieldDataTypes.AnalyzerConfig memory _config = config;

        // 1. Current APY
        uint256 currentAPY = vault.getCurrentAPY();

        // 2. Estimated Waiting Yield
        // Formula: estimatedWaitingYield = principal * currentAPY * waitingPeriod / (10000 * 365 days)
        uint256 estimatedWaitingYield = (principal * currentAPY * _config.waitingPeriod) / (BPS_DENOMINATOR * DAYS_365);

        // 3. Opportunity Cost
        // Convert volatility to BPS (volatility is 1e18 = 100%)
        uint256 volatilityBps = (marketState.volatility * BPS_DENOMINATOR) / ONE_E18;

        // Convert price deviation to BPS relative to TWAP
        uint256 deviationBps = 0;
        if (marketState.twap > 0) {
            uint256 absDeviation = marketState.priceDeviation < 0
                ? uint256(-marketState.priceDeviation)
                : uint256(marketState.priceDeviation);
            deviationBps = (absDeviation * BPS_DENOMINATOR) / marketState.twap;
        }

        // Apply configurable weights
        uint256 weightedVol = (volatilityBps * _config.volatilityWeightBps) / BPS_DENOMINATOR;
        uint256 weightedDev = (deviationBps * _config.deviationWeightBps) / BPS_DENOMINATOR;

        uint256 marketRiskBps = weightedVol + weightedDev;
        if (marketRiskBps > BPS_DENOMINATOR) {
            marketRiskBps = BPS_DENOMINATOR;
        }

        uint256 opportunityCost = (principal * marketRiskBps) / BPS_DENOMINATOR;

        // 4. Waiting Benefit
        int256 waitingBenefit = int256(estimatedWaitingYield) - int256(opportunityCost);

        // 5. Urgency
        uint256 urgency = 0;
        if (maxDelay == 0) {
            urgency = currentDelay > 0 ? BPS_DENOMINATOR : 0;
        } else {
            urgency = (currentDelay * BPS_DENOMINATOR) / maxDelay;
        }
        if (urgency > BPS_DENOMINATOR) {
            urgency = BPS_DENOMINATOR;
        }

        // 6. Remaining Delay
        uint256 remainingDelay = maxDelay > currentDelay ? maxDelay - currentDelay : 0;

        // 7. Recommendation Signal
        YieldDataTypes.Recommendation recommendation;
        if (urgency >= _config.urgencyThresholdBps || waitingBenefit < 0) {
            recommendation = YieldDataTypes.Recommendation.EXECUTE;
        } else if (waitingBenefit > 0 && urgency < _config.urgencyThresholdBps) {
            recommendation = YieldDataTypes.Recommendation.WAIT;
        } else {
            recommendation = YieldDataTypes.Recommendation.NEUTRAL;
        }

        return YieldDataTypes.YieldAnalysis({
            currentAPY: currentAPY,
            estimatedWaitingYield: estimatedWaitingYield,
            opportunityCost: opportunityCost,
            waitingBenefit: waitingBenefit,
            urgency: urgency,
            remainingDelay: remainingDelay,
            recommendation: recommendation
        });
    }
}
