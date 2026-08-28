import { contracts } from "../contracts/provider";

export async function getYieldAnalysisForStrategy(strategyId: string | number) {
  try {
    const rawStrategy = await contracts.dcaEngine.getStrategy(strategyId);
    const rawMarket = await contracts.marketAnalyzer["getMarketState()"]();
    const shares = await contracts.yieldVault.balanceOf(rawStrategy.owner);
    const availableCapital = await contracts.yieldVault.convertToAssets(shares);
    const currentDelay = await contracts.dcaEngine.getRemainingDelay(strategyId);
    
    const rawYield = await contracts.yieldAnalyzer.analyzeYieldOpportunity(
      availableCapital,
      rawMarket,
      currentDelay,
      rawStrategy.maxDelay
    );
    
    return {
      currentAPY: rawYield.currentAPY.toString(),
      estimatedWaitingYield: rawYield.estimatedWaitingYield.toString(),
      opportunityCost: rawYield.opportunityCost.toString(),
      waitingBenefit: rawYield.waitingBenefit.toString(),
      urgency: rawYield.urgency.toString(),
      remainingDelay: rawYield.remainingDelay.toString(),
      recommendation: Number(rawYield.recommendation)
    };
  } catch (error) {
    console.error("Error fetching yield analysis:", error);
    return null;
  }
}

export async function getYieldStateForUser(userAddress: string) {
  const state = await contracts.yieldAnalyzer.getYieldStateForUser(userAddress);
  return formatYieldState(state);
}

export async function getYieldStateForAmount(amount: string) {
  const state = await contracts.yieldAnalyzer.getYieldStateForAmount(amount);
  return formatYieldState(state);
}

function formatYieldState(state: any) {
  return {
    currentAPY: state.currentAPY.toString(),
    principalAssets: state.principalAssets.toString(),
    projectedYield7D: state.projectedYield7D.toString(),
    projectedYield30D: state.projectedYield30D.toString(),
    projectedYield365D: state.projectedYield365D.toString()
  };
}
