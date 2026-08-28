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
