// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketDataTypes} from "../market/MarketDataTypes.sol";

/**
 * @title IMarketDataProvider
 * @notice Interface for retrieving raw market data.
 * @dev All monetary values use 1e18 fixed‑point representation unless otherwise noted.
 */
interface IMarketDataProvider {
    /// @notice Returns the current asset price (1e18 fixed point).
    function getCurrentPrice() external view returns (uint256);

    /// @notice Returns the time‑weighted average price (1e18 fixed point).
    function getTWAP() external view returns (uint256);

    /// @notice Returns the volatility scalar (1e18 fixed point).
    function getVolatility() external view returns (uint256);

    /// @notice Returns the available liquidity in underlying asset units.
    function getLiquidity() external view returns (uint256);

    /// @notice Returns the identifier of the data source.
    function getDataSource() external view returns (bytes32);

    /// @notice Returns the timestamp of the snapshot (seconds since epoch).
    function getTimestamp() external view returns (uint256);

    /// @notice Returns all raw market data in a single struct.
    function getRawData() external view returns (MarketDataTypes.RawMarketData memory);
}
