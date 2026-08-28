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
