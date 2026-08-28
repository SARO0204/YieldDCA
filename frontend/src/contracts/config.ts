import { Contract, type Signer } from 'ethers';

import dcaEngineAbi from './abis/DCAEngine.json';
import yieldVaultAbi from './abis/YieldVault.json';
import mockErc20Abi from './abis/MockERC20.json';

// Use environment variables or fallback to hardcoded ones for local anvil
export const addresses = {
  dcaEngine: import.meta.env.VITE_DCA_ENGINE_ADDRESS || "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  yieldVault: import.meta.env.VITE_YIELD_VAULT_ADDRESS || "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  mockErc20: import.meta.env.VITE_MOCK_ERC20_ADDRESS || "0x5FbDB2315678afecb367f032d93F642f64180aa3"
};

export const contracts = {
  dcaEngine: (signer: Signer) => new Contract(addresses.dcaEngine, dcaEngineAbi, signer),
  yieldVault: (signer: Signer) => new Contract(addresses.yieldVault, yieldVaultAbi, signer),
  mockErc20: (signer: Signer) => new Contract(addresses.mockErc20, mockErc20Abi, signer),
};
