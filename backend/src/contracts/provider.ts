import { JsonRpcProvider, Contract } from "ethers";
import { loadConfig } from "../config";

import dcaEngineAbi from "./abis/DCAEngine.json";
import yieldVaultAbi from "./abis/YieldVault.json";
import marketAnalyzerAbi from "./abis/MarketAnalyzer.json";
import yieldAnalyzerAbi from "./abis/YieldAnalyzer.json";
import mockErc20Abi from "./abis/MockERC20.json";

import decisionEngineAbi from "./abis/DecisionEngine.json";
import executionManagerAbi from "./abis/ExecutionManager.json";
import mockSwapExecutorAbi from "./abis/MockSwapExecutor.json";
import mockMarketProviderAbi from "./abis/MockMarketDataProvider.json";

const config = loadConfig();

export const provider = new JsonRpcProvider(config.rpcUrl, config.chainId);

export const contracts = {
  dcaEngine: new Contract(config.contracts.dcaEngine, dcaEngineAbi, provider),
  yieldVault: new Contract(config.contracts.yieldVault, yieldVaultAbi, provider),
  marketAnalyzer: new Contract(config.contracts.marketAnalyzer, marketAnalyzerAbi, provider),
  yieldAnalyzer: new Contract(config.contracts.yieldAnalyzer, yieldAnalyzerAbi, provider),
  mockErc20: new Contract(config.contracts.mockErc20, mockErc20Abi, provider),
  decisionEngine: new Contract(config.contracts.decisionEngine, decisionEngineAbi.abi, provider),
  executionManager: new Contract(config.contracts.executionManager, executionManagerAbi.abi, provider),
  mockSwapExecutor: new Contract(config.contracts.mockSwapExecutor, mockSwapExecutorAbi.abi, provider),
  mockMarketProvider: config.contracts.mockMarketProvider ? new Contract(config.contracts.mockMarketProvider, mockMarketProviderAbi.abi, provider) : undefined,
};
