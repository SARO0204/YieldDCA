import { contracts } from "../contracts/provider";

export async function getMarketState(tradeSize?: string) {
  let state;
  if (tradeSize && tradeSize !== "0") {
    state = await contracts.marketAnalyzer["getMarketState(uint256)"](tradeSize);
  } else {
    state = await contracts.marketAnalyzer["getMarketState()"]();
  }
  
  return {
    currentPrice: state.currentPrice.toString(),
    twap: state.twap.toString(),
    priceDeviation: state.priceDeviation.toString(),
    volatility: state.volatility.toString(),
    liquidity: state.liquidity.toString(),
    estimatedSlippage: state.estimatedSlippage.toString(),
    estimatedPriceImpact: state.estimatedPriceImpact.toString(),
    timestamp: state.timestamp.toString(),
    dataSource: state.dataSource
  };
}
