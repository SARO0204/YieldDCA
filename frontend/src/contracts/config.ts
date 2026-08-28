import { Contract, type Signer } from 'ethers';

import dcaEngineAbi from './abis/DCAEngine.json';
import yieldVaultAbi from './abis/YieldVault.json';
import mockErc20Abi from './abis/MockERC20.json';
import decisionEngineAbi from './abis/DecisionEngine.json';
import executionManagerAbi from './abis/ExecutionManager.json';
import mockSwapExecutorAbi from './abis/MockSwapExecutor.json';

// Use environment variables or fallback to hardcoded ones for local anvil
export const addresses = {
  dcaEngine: import.meta.env.VITE_DCA_ENGINE_ADDRESS || "0x59E3983CB92D4C6E2871Ef7c9968EBD7e24493d7",
  yieldVault: import.meta.env.VITE_YIELD_VAULT_ADDRESS || "0xc5199f8B51b83c54fDcb9D21EcEfD6998c388a53",
  mockErc20: import.meta.env.VITE_MOCK_ERC20_ADDRESS || "0xA2C3625C7D24f95D34EA971d283514065DCE510f",
  mockWeth: import.meta.env.VITE_MOCK_WETH_ADDRESS || "0xaB9a04BAb9aD01E59d3514D5C7b0E3Dab8a22818",
  decisionEngine: import.meta.env.VITE_DECISION_ENGINE_ADDRESS || "0x3D87627655a451345fDA0e9067F40c23242ba9C9",
  executionManager: import.meta.env.VITE_EXECUTION_MANAGER_ADDRESS || "0xa5FEE0d811D338ea779a24e98963c76c62e7aD92",
  mockSwapExecutor: import.meta.env.VITE_MOCK_SWAP_EXECUTOR_ADDRESS || "0xa606eCc801c7e55B02aF3B0991Dc993D5D6d7d17",
};

export const contracts = {
  dcaEngine: (signer: Signer) => new Contract(addresses.dcaEngine, dcaEngineAbi, signer),
  yieldVault: (signer: Signer) => new Contract(addresses.yieldVault, yieldVaultAbi, signer),
  mockErc20: (signer: Signer) => new Contract(addresses.mockErc20, mockErc20Abi, signer),
  decisionEngine: (signer: Signer) => new Contract(addresses.decisionEngine, decisionEngineAbi.abi, signer),
  executionManager: (signer: Signer) => new Contract(addresses.executionManager, executionManagerAbi.abi, signer),
  mockSwapExecutor: (signer: Signer) => new Contract(addresses.mockSwapExecutor, mockSwapExecutorAbi.abi, signer),
};
