import dotenv from "dotenv";
dotenv.config();

export interface AppConfig {
  port: number;
  rpcUrl: string;
  chainId: number;
  contracts: {
    dcaEngine: string;
    yieldVault: string;
    marketAnalyzer: string;
    mockMarketProvider: string;
    yieldAnalyzer: string;
    mockErc20: string;
    decisionEngine: string;
    executionManager: string;
    mockSwapExecutor: string;
  };
  scheduler: {
    enabled: boolean;
    intervalMs: number;
    maxRetries: number;
  };
}

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function optionalEnv(key: string, fallback: string): string {
  return process.env[key] || fallback;
}

export function loadConfig(): AppConfig {
  return {
    port: parseInt(optionalEnv("PORT", "3000"), 10),
    rpcUrl: optionalEnv("RPC_URL", "http://127.0.0.1:8545"),
    chainId: parseInt(optionalEnv("CHAIN_ID", "31337"), 10),
    contracts: {
      dcaEngine: requireEnv("DCA_ENGINE_ADDRESS"),
      yieldVault: requireEnv("YIELD_VAULT_ADDRESS"),
      marketAnalyzer: requireEnv("MARKET_ANALYZER_ADDRESS"),
      mockMarketProvider: optionalEnv("MOCK_MARKET_PROVIDER_ADDRESS", ""),
      yieldAnalyzer: requireEnv("YIELD_ANALYZER_ADDRESS"),
      mockErc20: requireEnv("MOCK_ERC20_ADDRESS"),
      decisionEngine: requireEnv("DECISION_ENGINE_ADDRESS"),
      executionManager: requireEnv("EXECUTION_MANAGER_ADDRESS"),
      mockSwapExecutor: requireEnv("MOCK_SWAP_EXECUTOR_ADDRESS"),
    },
    scheduler: {
      enabled: optionalEnv("SCHEDULER_ENABLED", "false") === "true",
      intervalMs: parseInt(optionalEnv("SCHEDULER_INTERVAL_MS", "60000"), 10),
      maxRetries: parseInt(optionalEnv("SCHEDULER_MAX_RETRIES", "3"), 10),
    }
  };
}
