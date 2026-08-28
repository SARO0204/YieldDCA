// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMarketDataProvider} from "../interfaces/IMarketDataProvider.sol";
import {MarketDataTypes} from "./MarketDataTypes.sol";

/**
 * @title MarketAnalyzer
 * @notice Provides a view‑only normalized market state derived from an IMarketDataProvider.
 * @dev All calculations are deterministic and suitable for unit‑testing. The contract is immutable after deployment.
 */
contract MarketAnalyzer {
    IMarketDataProvider public immutable provider;

    error InvalidProvider();
    error InvalidLiquidity();

    /**
     * @dev Deploy with the address of a market‑data provider. Zero address is disallowed.
     */
    constructor(address providerAddress) {
        if (providerAddress == address(0)) revert InvalidProvider();
        provider = IMarketDataProvider(providerAddress);
    }

    /**
     * @notice Returns the market state with a trade size of zero.
     */
    function getMarketState() external view returns (MarketDataTypes.MarketState memory) {
        return _calculateState(0);
    }

    /**
     * @notice Returns the market state for a given trade size.
     * @param tradeSize Amount of underlying asset to be swapped (in token units, matching liquidity decimals).
     */
    function getMarketState(uint256 tradeSize) external view returns (MarketDataTypes.MarketState memory) {
        return _calculateState(tradeSize);
    }

    function _calculateState(uint256 tradeSize) internal view returns (MarketDataTypes.MarketState memory) {
        MarketDataTypes.RawMarketData memory raw = provider.getRawData();

        int256 priceDeviation = int256(raw.currentPrice) - int256(raw.twap);
        uint256 volatilityBps = (raw.volatility * 10000) / 1e18;
        uint256 estimatedSlippage = volatilityBps / 2;
        uint256 estimatedPriceImpact = 0;
        
        if (tradeSize != 0) {
            if (raw.liquidity == 0) revert InvalidLiquidity();
            // simple price impact model for demo: impact in bps = (tradeSize * 10000) / liquidity
            // Note: In production this would be replaced with actual AMM curves.
            estimatedPriceImpact = (tradeSize * 10000) / raw.liquidity;
        }

        return MarketDataTypes.MarketState({
            currentPrice: raw.currentPrice,
            twap: raw.twap,
            priceDeviation: priceDeviation,
            volatility: raw.volatility,
            liquidity: raw.liquidity,
            estimatedSlippage: estimatedSlippage,
            estimatedPriceImpact: estimatedPriceImpact,
            timestamp: raw.timestamp,
            dataSource: raw.dataSource
        });
    }
}
