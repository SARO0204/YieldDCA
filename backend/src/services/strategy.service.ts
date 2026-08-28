import { contracts } from "../contracts/provider";

export async function getStrategy(strategyId: string | number) {
  const strategy = await contracts.dcaEngine.getStrategy(strategyId);
  return {
    owner: strategy.owner,
    inputToken: strategy.inputToken,
    targetToken: strategy.targetToken,
    targetAllocation: strategy.targetAllocation.toString(),
    frequency: strategy.frequency.toString(),
    maxDelay: strategy.maxDelay.toString(),
    minExecutionAmount: strategy.minExecutionAmount.toString(),
    maxExecutionAmount: strategy.maxExecutionAmount.toString(),
    nextExecutionTime: strategy.nextExecutionTime.toString(),
    status: Number(strategy.status)
  };
}

export async function getUserStrategies(userAddress: string) {
  const strategyIds = await contracts.dcaEngine.getUserStrategies(userAddress);
  return strategyIds.map((id: bigint) => id.toString());
}

export async function getStrategyCount() {
  const count = await contracts.dcaEngine.getStrategyCount();
  return count.toString();
}

export async function checkExecutionStatus(strategyId: string | number) {
  const [isDue, isWindowOpen, isOverdue, remainingDelay] = await Promise.all([
    contracts.dcaEngine.isExecutionDue(strategyId),
    contracts.dcaEngine.isExecutionWindowOpen(strategyId),
    contracts.dcaEngine.isOverdue(strategyId),
    contracts.dcaEngine.getRemainingDelay(strategyId)
  ]);
  
  return {
    isDue,
    isWindowOpen,
    isOverdue,
    remainingDelay: remainingDelay.toString()
  };
}

export async function getActiveStrategies() {
  const count = await getStrategyCount();
  const activeIds: string[] = [];
  for (let i = 1; i <= Number(count); i++) {
    try {
      const strat = await contracts.dcaEngine.getStrategy(i);
      if (Number(strat.status) === 1) { // ACTIVE
        activeIds.push(i.toString());
      }
    } catch (e) {
      // Ignore not found
    }
  }
  return activeIds;
}

export async function getStrategyState(strategyId: string | number) {
  const strategy = await getStrategy(strategyId);
  let record: any = { totalExecuted: "0", lastExecutionTimestamp: "0", nonce: "0" };
  try {
    const rec = await contracts.executionManager.getExecutionRecord(strategyId);
    record = {
      totalExecuted: rec.totalExecuted.toString(),
      lastExecutionTimestamp: rec.lastExecutionTimestamp.toString(),
      nonce: rec.nonce.toString()
    };
  } catch (e) {
    // defaults
  }
  return {
    ...strategy,
    record
  };
}
