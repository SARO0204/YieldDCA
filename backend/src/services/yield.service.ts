import { contracts } from "../contracts/provider";

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
