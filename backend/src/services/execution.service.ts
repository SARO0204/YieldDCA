import { contracts } from "../contracts/provider";

export async function getExecutionRecord(strategyId: string | number) {
  try {
    const record = await contracts.executionManager.getExecutionRecord(strategyId);
    return {
      totalExecuted: record.totalExecuted.toString(),
      lastExecutionTimestamp: record.lastExecutionTimestamp.toString(),
      lastExecutionAmount: record.lastExecutionAmount.toString(),
      executionCount: record.executionCount.toString(),
      nonce: record.nonce.toString()
    };
  } catch (error) {
    // Return default if error (e.g. strategy not found or not initialized)
    return {
      totalExecuted: "0",
      lastExecutionTimestamp: "0",
      lastExecutionAmount: "0",
      executionCount: "0",
      nonce: "0"
    };
  }
}

export async function getRemainingAllocation(strategyId: string | number) {
  try {
    const remaining = await contracts.executionManager.getRemainingAllocation(strategyId);
    return remaining.toString();
  } catch (error) {
    return "0";
  }
}

export async function prepareExecution(strategyId: string | number, executionAmount: string, nonce: string) {
  // Mock decision tuple for the scheduler
  const decisionResultTuple = {
    action: 1, // EXECUTE
    targetAmount: "0",
    executionAmount: executionAmount,
    remainingAmount: "0",
    recommendedDelay: "0",
    score: "0",
    reason: "Scheduler Automated Execution",
    timestamp: Math.floor(Date.now() / 1000),
    diagnostics: ""
  };
  
  const [validatedAmount, remainingAfter] = await contracts.executionManager.validateExecution(
    strategyId,
    decisionResultTuple,
    nonce
  );

  const tx = await contracts.executionManager.executeDecision.populateTransaction(
    strategyId,
    decisionResultTuple,
    nonce,
    "0" // minSwapOutput
  );

  return {
    to: tx.to,
    data: tx.data,
    value: tx.value?.toString() || "0"
  };
}
