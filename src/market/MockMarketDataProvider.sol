// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketDataProvider} from "../interfaces/IMarketDataProvider.sol";
import {MarketDataTypes} from "./MarketDataTypes.sol";

/**
 * @title MockMarketDataProvider
 * @notice Deterministic mock implementation of IMarketDataProvider for testing and local development.
 * @dev All values are stored in 1e18 fixed-point where applicable.
 */
contract MockMarketDataProvider is IMarketDataProvider, Ownable {
    // Raw market data storage
    uint256 private _currentPrice = 3000e18;
    uint256 private _twap = 2950e18;
    uint256 private _volatility = 0.1e18; // 10% volatility
    uint256 private _liquidity = 1_000_000e6; // Assume token with 6 decimals (e.g., USDC)
    bytes32 private _dataSource = keccak256("MOCK_SIMULATED_MARKET_DATA");
    uint256 private _timestamp = block.timestamp;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Owner-only setters to adjust mock data.
     */
    function setCurrentPrice(uint256 price) external onlyOwner {
        _currentPrice = price;
    }

    function setTWAP(uint256 twap) external onlyOwner {
        _twap = twap;
    }

    function setVolatility(uint256 vol) external onlyOwner {
        _volatility = vol;
    }

    function setLiquidity(uint256 liq) external onlyOwner {
        _liquidity = liq;
    }

    function setDataSource(bytes32 src) external onlyOwner {
        _dataSource = src;
    }

    function setTimestamp(uint256 ts) external onlyOwner {
        _timestamp = ts;
    }

    function setRawData(MarketDataTypes.RawMarketData memory data) external onlyOwner {
        _currentPrice = data.currentPrice;
        _twap = data.twap;
        _volatility = data.volatility;
        _liquidity = data.liquidity;
        _dataSource = data.dataSource;
        _timestamp = data.timestamp;
    }

    // IMarketDataProvider interface implementations
    function getCurrentPrice() external view override returns (uint256) {
        return _currentPrice;
    }

    function getTWAP() external view override returns (uint256) {
        return _twap;
    }

    function getVolatility() external view override returns (uint256) {
        return _volatility;
    }

    function getLiquidity() external view override returns (uint256) {
        return _liquidity;
    }

    function getDataSource() external view override returns (bytes32) {
        return _dataSource;
    }

    function getTimestamp() external view override returns (uint256) {
        return _timestamp;
    }

    function getRawData() external view override returns (MarketDataTypes.RawMarketData memory) {
        return MarketDataTypes.RawMarketData({
            currentPrice: _currentPrice,
            twap: _twap,
            volatility: _volatility,
            liquidity: _liquidity,
            dataSource: _dataSource,
            timestamp: _timestamp
        });
    }
}
