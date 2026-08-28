import { contracts } from "../contracts/provider";
import { getExecutionRecord } from "./execution.service";

export async function getDecision(strategyId: string | number) {
  try {
    const rawStrategy = await contracts.dcaEngine.getStrategy(strategyId);
    const rawMarket = await contracts.marketAnalyzer["getMarketState()"]();

    // Get capital available from vault for the strategy owner
    const shares = await contracts.yieldVault.balanceOf(rawStrategy.owner);
    const availableCapital = await contracts.yieldVault.convertToAssets(shares);

    // Current delay for the strategy
    const currentDelay = await contracts.dcaEngine.getRemainingDelay(strategyId);

    // YieldAnalyzer.analyzeYieldOpportunity(principal, marketState, currentDelay, maxDelay)
    const rawYield = await contracts.yieldAnalyzer.analyzeYieldOpportunity(
      availableCapital,
      rawMarket,
      currentDelay,
      rawStrategy.maxDelay
    );

    // Execution context for the decision engine
    const executionRecord = await getExecutionRecord(strategyId);

    const context = {
      lastExecutionTimestamp: BigInt(executionRecord.lastExecutionTimestamp),
      lastExecutionAmount: BigInt(executionRecord.lastExecutionAmount),
      totalExecutedSoFar: BigInt(executionRecord.totalExecuted)
    };

    const result = await contracts.decisionEngine.evaluate(
      rawStrategy,
      rawMarket,
      rawYield,
      availableCapital,
      currentDelay,
      context
    );

    // Safely serialize diagnostics (BigInt fields)
    const diag = result.diagnostics;
    const safeDiag: Record<string, any> = {};
    for (const key of Object.keys(Object.assign({}, diag))) {
      const val = diag[key];
      if (typeof val === "bigint") {
        safeDiag[key] = val.toString();
      } else if (typeof val === "boolean") {
        safeDiag[key] = val;
      } else {
        safeDiag[key] = val?.toString?.() ?? val;
      }
    }

    return {
      action: Number(result.action),
      targetAmount: result.targetAmount.toString(),
      executionAmount: result.executionAmount.toString(),
      remainingAmount: result.remainingAmount.toString(),
      recommendedDelay: result.recommendedDelay.toString(),
      score: result.score.toString(),
      reason: result.reason,
      timestamp: result.timestamp.toString(),
      diagnostics: safeDiag
    };
  } catch (error) {
    console.error("Error generating decision:", error);
    return null;
  }
}
