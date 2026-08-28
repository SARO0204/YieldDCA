import { getStrategy, checkExecutionStatus } from "./strategy.service";
import { getVaultState, getUserVaultData } from "./vault.service";
import { getMarketState } from "./market.service";
import { getYieldStateForUser, getYieldStateForAmount } from "./yield.service";
import { getDecision } from "./decision.service";
import { getExecutionRecord } from "./execution.service";

export async function getDashboardData(userAddress?: string, strategyId?: string) {
  // Aggregate all state in parallel where possible
  const [vaultState, marketState] = await Promise.all([
    getVaultState(),
    getMarketState()
  ]);

  let userVaultData = null;
  let yieldState = null;
  let strategyData = null;
  let executionStatus = null;
  let decisionData = null;
  let executionRecord = null;

  if (userAddress) {
    [userVaultData, yieldState] = await Promise.all([
      getUserVaultData(userAddress),
      getYieldStateForUser(userAddress)
    ]);
  } else {
    // Default to some nominal amount if no user is provided to show generic yield
    yieldState = await getYieldStateForAmount(vaultState.totalAssets || "0");
  }

  if (strategyId) {
    try {
      strategyData = await getStrategy(strategyId);
      [executionStatus, decisionData, executionRecord] = await Promise.all([
        checkExecutionStatus(strategyId),
        getDecision(strategyId),
        getExecutionRecord(strategyId)
      ]);
    } catch (error) {
      // Strategy might not exist
      strategyData = null;
    }
  }

  return {
    vault: {
      ...vaultState,
      user: userVaultData
    },
    market: marketState,
    yield: yieldState,
    strategy: strategyData ? {
      ...strategyData,
      execution: executionStatus,
      decision: decisionData,
      record: executionRecord
    } : null
  };
}
