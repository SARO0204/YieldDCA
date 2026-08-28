// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketAnalyzer} from "../src/market/MarketAnalyzer.sol";
import {MockMarketDataProvider} from "../src/market/MockMarketDataProvider.sol";
import {MarketDataTypes} from "../src/market/MarketDataTypes.sol";

contract MarketAnalyzerTest is Test {
    MarketAnalyzer public analyzer;
    MockMarketDataProvider public mockProvider;

    function setUp() public {
        mockProvider = new MockMarketDataProvider();
        analyzer = new MarketAnalyzer(address(mockProvider));
    }

    function test_RevertsIfProviderIsZeroAddress() public {
        vm.expectRevert(MarketAnalyzer.InvalidProvider.selector);
        new MarketAnalyzer(address(0));
    }

    function test_GetMarketState_ZeroTradeSize() public {
        // Set mock data
        MarketDataTypes.RawMarketData memory data = MarketDataTypes.RawMarketData({
            currentPrice: 2000e18,
            twap: 1950e18,
            volatility: 0.05e18, // 5%
            liquidity: 100_000e18,
            dataSource: bytes32("MOCK_ORACLE"),
            timestamp: block.timestamp
        });
        mockProvider.setRawData(data);

        // Fetch MarketState
        MarketDataTypes.MarketState memory state = analyzer.getMarketState();

        // Validate
        assertEq(state.currentPrice, 2000e18);
        assertEq(state.twap, 1950e18);
        assertEq(state.priceDeviation, 50e18);
        
        // volatility is 0.05e18. 0.05e18 * 10000 / 1e18 = 500 bps
        assertEq(state.volatility, 0.05e18);
        
        // estimatedSlippage = volatilityBps / 2 = 500 / 2 = 250 bps
        assertEq(state.estimatedSlippage, 250);
        
        // trade size is 0, so price impact is 0
        assertEq(state.estimatedPriceImpact, 0);

        assertEq(state.liquidity, 100_000e18);
        assertEq(state.timestamp, block.timestamp);
        assertEq(state.dataSource, bytes32("MOCK_ORACLE"));
    }

    function test_GetMarketState_WithTradeSize() public {
        MarketDataTypes.RawMarketData memory data = MarketDataTypes.RawMarketData({
            currentPrice: 2000e18,
            twap: 2050e18,
            volatility: 0.02e18, // 2% -> 200 bps
            liquidity: 50_000e18,
            dataSource: bytes32("MOCK_ORACLE"),
            timestamp: block.timestamp
        });
        mockProvider.setRawData(data);

        uint256 tradeSize = 1_000e18; // 1,000 ETH
        MarketDataTypes.MarketState memory state = analyzer.getMarketState(tradeSize);

        // priceDeviation = 2000e18 - 2050e18 = -50e18
        assertEq(state.priceDeviation, -50e18);

        // volatility = 200 bps -> slippage = 100 bps
        assertEq(state.estimatedSlippage, 100);

        // priceImpact = (tradeSize * 10000) / liquidity = (1_000e18 * 10000) / 50_000e18 = 10000 / 50 = 200 bps
        assertEq(state.estimatedPriceImpact, 200);
    }

    function test_RevertsIfLiquidityZeroWithTradeSize() public {
        MarketDataTypes.RawMarketData memory data = MarketDataTypes.RawMarketData({
            currentPrice: 2000e18,
            twap: 2000e18,
            volatility: 0.02e18,
            liquidity: 0,
            dataSource: bytes32("MOCK_ORACLE"),
            timestamp: block.timestamp
        });
        mockProvider.setRawData(data);

        vm.expectRevert(MarketAnalyzer.InvalidLiquidity.selector);
        analyzer.getMarketState(100e18);
    }
}
