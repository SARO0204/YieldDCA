import { ethers } from 'ethers';
import { contracts } from '../contracts/config';

// Re-export the read functions from API (which we still use for aggregation)
export * from './api';

// Transaction functions for DCAEngine
export async function createStrategy(provider: ethers.BrowserProvider, params: any) {
  const signer = await provider.getSigner();
  const dcaEngine = contracts.dcaEngine(signer);
  const tx = await dcaEngine.createStrategy(params);
  return await tx.wait();
}

export async function pauseStrategy(provider: ethers.BrowserProvider, strategyId: string) {
  const signer = await provider.getSigner();
  const dcaEngine = contracts.dcaEngine(signer);
  const tx = await dcaEngine.pauseStrategy(strategyId);
  return await tx.wait();
}

export async function resumeStrategy(provider: ethers.BrowserProvider, strategyId: string) {
  const signer = await provider.getSigner();
  const dcaEngine = contracts.dcaEngine(signer);
  const tx = await dcaEngine.resumeStrategy(strategyId);
  return await tx.wait();
}

export async function cancelStrategy(provider: ethers.BrowserProvider, strategyId: string) {
  const signer = await provider.getSigner();
  const dcaEngine = contracts.dcaEngine(signer);
  const tx = await dcaEngine.cancelStrategy(strategyId);
  return await tx.wait();
}

// Transaction functions for YieldVault
export async function depositVault(provider: ethers.BrowserProvider, amount: string, receiver: string) {
  const signer = await provider.getSigner();
  const vault = contracts.yieldVault(signer);
  const mockErc20 = contracts.mockErc20(signer);
  
  // Approve first
  const approveTx = await mockErc20.approve(await vault.getAddress(), amount);
  await approveTx.wait();
  
  const tx = await vault.deposit(amount, receiver);
  return await tx.wait();
}

export async function withdrawVault(provider: ethers.BrowserProvider, amount: string, receiver: string, owner: string) {
  const signer = await provider.getSigner();
  const vault = contracts.yieldVault(signer);
  const tx = await vault.withdraw(amount, receiver, owner);
  return await tx.wait();
}

// Faucet for testing
export async function mintUsdc(provider: ethers.BrowserProvider, amount: string, to: string) {
  const signer = await provider.getSigner();
  const mockErc20 = contracts.mockErc20(signer);
  const tx = await mockErc20.mint(to, amount);
  return await tx.wait();
}

// Module 6: ExecutionManager integration
export async function executeDecision(
  provider: ethers.BrowserProvider,
  strategyId: string,
  decision: any,
  expectedNonce: string,
  minSwapOutput: string
) {
  const signer = await provider.getSigner();
  const executionManager = contracts.executionManager(signer);
  
  // decision parameter needs to match IDecisionEngine.DecisionResult struct
  const tx = await executionManager.executeDecision(
    strategyId,
    {
      action: decision.action,
      targetAmount: decision.targetAmount,
      executionAmount: decision.executionAmount,
      remainingAmount: decision.remainingAmount,
      recommendedDelay: decision.recommendedDelay,
      score: decision.score,
      reason: decision.reason,
      timestamp: decision.timestamp,
      diagnostics: {
        price: decision.diagnostics.price,
        twap: decision.diagnostics.twap,
        priceDeviation: decision.diagnostics.priceDeviation,
        volatility: decision.diagnostics.volatility,
        liquidity: decision.diagnostics.liquidity,
        slippage: decision.diagnostics.slippage,
        priceImpact: decision.diagnostics.priceImpact,
        currentAPY: decision.diagnostics.currentAPY,
        estimatedWaitingYield: decision.diagnostics.estimatedWaitingYield,
        opportunityCost: decision.diagnostics.opportunityCost,
        waitingBenefit: decision.diagnostics.waitingBenefit,
        marketScore: decision.diagnostics.marketScore,
        yieldScore: decision.diagnostics.yieldScore,
        strategyScore: decision.diagnostics.strategyScore,
        minimumExecutionSatisfied: decision.diagnostics.minimumExecutionSatisfied,
        maximumExecutionSatisfied: decision.diagnostics.maximumExecutionSatisfied,
        remainingAllocationSatisfied: decision.diagnostics.remainingAllocationSatisfied,
        capitalAvailable: decision.diagnostics.capitalAvailable,
        delayAllowed: decision.diagnostics.delayAllowed,
        strategyActive: decision.diagnostics.strategyActive
      }
    },
    expectedNonce,
    minSwapOutput
  );
  return await tx.wait();
}
