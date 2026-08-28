// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MarketDataTypes
 * @notice Struct definitions for raw market data and normalized market state.
 * @dev All monetary values use 1e18 fixed-point representation unless otherwise noted.
 */
library MarketDataTypes {
    /**
     * @dev Raw data directly fetched from a market data provider.
     * @param currentPrice Current asset price, 1e18 fixed point.
     * @param twap Time-weighted average price, 1e18 fixed point.
     * @param volatility Volatility scalar, 1e18 where 1e18 = 100%.
     * @param liquidity Available liquidity in underlying asset units.
     * @param dataSource Identifier of the data source (e.g. keccak256 hash).
     * @param timestamp Unix timestamp of the snapshot.
     */
    struct RawMarketData {
        uint256 currentPrice;
        uint256 twap;
        uint256 volatility;
        uint256 liquidity;
        bytes32 dataSource;
        uint256 timestamp;
    }

    /**
     * @dev Normalized market state consumed by decision-engine modules.
     * @param currentPrice Current asset price, 1e18.
     * @param twap Time-weighted average price, 1e18.
     * @param priceDeviation Signed deviation (current - twap), 1e18.
     * @param volatility Volatility scalar, 1e18.
     * @param liquidity Available liquidity, token units.
     * @param estimatedSlippage Estimated slippage in basis points.
     * @param estimatedPriceImpact Estimated price impact in basis points.
     * @param timestamp Snapshot timestamp.
     * @param dataSource Identifier of the data source.
     */
    struct MarketState {
        uint256 currentPrice;
        uint256 twap;
        int256 priceDeviation;
        uint256 volatility;
        uint256 liquidity;
        uint256 estimatedSlippage;
        uint256 estimatedPriceImpact;
        uint256 timestamp;
        bytes32 dataSource;
    }
}
