import { describe, it, expect, vi, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../server';

vi.mock('../contracts/provider', () => ({
  contracts: {
    dcaEngine: {
      createStrategy: { populateTransaction: vi.fn().mockResolvedValue({ to: "0x123", data: "0xabc", value: "0" }) },
      updateStrategy: { populateTransaction: vi.fn().mockResolvedValue({ to: "0x123", data: "0xabc", value: "0" }) },
      pauseStrategy: { populateTransaction: vi.fn().mockResolvedValue({ to: "0x123", data: "0xabc", value: "0" }) },
      resumeStrategy: { populateTransaction: vi.fn().mockResolvedValue({ to: "0x123", data: "0xabc", value: "0" }) },
      getStrategy: vi.fn(),
      getUserStrategies: vi.fn(),
      getRemainingDelay: vi.fn(),
      isExecutionDue: vi.fn(),
      isExecutionWindowOpen: vi.fn(),
      isOverdue: vi.fn()
    },
    yieldVault: {
      balanceOf: vi.fn(),
      convertToAssets: vi.fn(),
      totalAssets: vi.fn(),
      simulatedAPY: vi.fn()
    },
    marketAnalyzer: {
      "getMarketState()": vi.fn(),
      "getMarketState(uint256)": vi.fn()
    },
    yieldAnalyzer: {
      analyzeYieldOpportunity: vi.fn(),
      getYieldStateForAmount: vi.fn(),
      getYieldStateForUser: vi.fn()
    },
    decisionEngine: {
      evaluate: vi.fn()
    },
    executionManager: {
      getExecutionRecord: vi.fn(),
      getRemainingAllocation: vi.fn(),
      validateExecution: vi.fn(),
      executeDecision: { populateTransaction: vi.fn().mockResolvedValue({ to: "0x123", data: "0xabc", value: "0" }) }
    }
  }
}));

import { contracts } from '../contracts/provider';

describe('API Tests', () => {

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Strategies API', () => {
    it('POST /api/strategies should return tx data', async () => {
      const res = await request(app)
        .post('/api/strategies')
        .send({
          inputToken: '0x1111111111111111111111111111111111111111',
          targetToken: '0x2222222222222222222222222222222222222222',
          targetAllocation: "1000",
          frequency: "86400",
          maxDelay: "3600",
          minExecutionAmount: "10",
          maxExecutionAmount: "100"
        });
      
      expect(res.status).toBe(200);
      expect(res.body.transaction).toBeDefined();
    });

    it('GET /api/strategies/:id should return strategy', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123',
        inputToken: '0xabc',
        targetToken: '0xdef',
        targetAllocation: 1000n,
        frequency: 86400n,
        maxDelay: 3600n,
        minExecutionAmount: 10n,
        maxExecutionAmount: 100n,
        nextExecutionTime: 0n,
        status: 1
      });

      const res = await request(app).get('/api/strategies/1');
      expect(res.status).toBe(200);
      expect(res.body.strategy.targetAllocation).toBe("1000");
    });
  });

  describe('Market State API', () => {
    it('GET /api/market-state/:strategyId should return market state', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 1
      });
      (contracts.marketAnalyzer["getMarketState(uint256)"] as any).mockResolvedValue({
        currentPrice: 1n, twap: 1n, priceDeviation: 0n, volatility: 0n,
        liquidity: 100n, estimatedSlippage: 0n, estimatedPriceImpact: 0n,
        timestamp: 0n, dataSource: "mock"
      });

      const res = await request(app).get('/api/market-state/1');
      expect(res.status).toBe(200);
      expect(res.body.marketState).toBeDefined();
    });
  });

  describe('Yield Analysis API', () => {
    it('GET /api/yield-analysis/:strategyId should return yield analysis', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 1
      });
      (contracts.marketAnalyzer["getMarketState()"] as any).mockResolvedValue({});
      (contracts.yieldVault.balanceOf as any).mockResolvedValue(100n);
      (contracts.yieldVault.convertToAssets as any).mockResolvedValue(100n);
      (contracts.dcaEngine.getRemainingDelay as any).mockResolvedValue(0n);
      (contracts.yieldAnalyzer.analyzeYieldOpportunity as any).mockResolvedValue({
        currentAPY: 1n, estimatedWaitingYield: 1n, opportunityCost: 1n, waitingBenefit: 1n,
        urgency: 1n, remainingDelay: 1n, recommendation: 1n
      });

      const res = await request(app).get('/api/yield-analysis/1');
      expect(res.status).toBe(200);
      expect(res.body.yieldAnalysis).toBeDefined();
    });
  });

  describe('Decision API', () => {
    it('POST /api/decision/:strategyId should evaluate and return decision', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 1
      });
      (contracts.executionManager.getExecutionRecord as any).mockResolvedValue({
        lastExecutionTimestamp: 0n, lastExecutionAmount: 0n, totalExecuted: 0n
      });
      (contracts.decisionEngine.evaluate as any).mockResolvedValue({
        action: 1n, targetAmount: 100n, executionAmount: 10n, remainingAmount: 90n,
        recommendedDelay: 0n, score: 50n, reason: "test", timestamp: 0n, diagnostics: {}
      });
      (contracts.marketAnalyzer["getMarketState()"] as any).mockResolvedValue({});
      (contracts.yieldVault.balanceOf as any).mockResolvedValue(100n);
      (contracts.yieldVault.convertToAssets as any).mockResolvedValue(100n);
      (contracts.dcaEngine.getRemainingDelay as any).mockResolvedValue(0n);
      (contracts.yieldAnalyzer.analyzeYieldOpportunity as any).mockResolvedValue({});

      const res = await request(app).post('/api/decision/1');
      expect(res.status).toBe(200);
      expect(res.body.decision.action).toBe(1);
    });

    it('POST /api/decision/:strategyId should return 409 if strategy is paused', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 2 // 2 = PAUSED
      });
      const res = await request(app).post('/api/decision/1');
      expect(res.status).toBe(409);
    });
  });

  describe('Execution API', () => {
    it('POST /api/execution/:strategyId should prepare tx when validation succeeds', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 1
      });
      (contracts.executionManager.getExecutionRecord as any).mockResolvedValue({
        lastExecutionTimestamp: 0n, lastExecutionAmount: 0n, totalExecuted: 0n, nonce: 0n
      });
      (contracts.decisionEngine.evaluate as any).mockResolvedValue({
        action: 1n, targetAmount: 100n, executionAmount: 10n, remainingAmount: 90n,
        recommendedDelay: 0n, score: 50n, reason: "test", timestamp: 0n, diagnostics: {}
      });
      (contracts.marketAnalyzer["getMarketState()"] as any).mockResolvedValue({});
      (contracts.yieldVault.balanceOf as any).mockResolvedValue(100n);
      (contracts.yieldVault.convertToAssets as any).mockResolvedValue(100n);
      (contracts.dcaEngine.getRemainingDelay as any).mockResolvedValue(0n);
      (contracts.yieldAnalyzer.analyzeYieldOpportunity as any).mockResolvedValue({});
      
      (contracts.executionManager.validateExecution as any).mockResolvedValue([10n, 90n]);

      const res = await request(app).post('/api/execution/1');
      expect(res.status).toBe(200);
      expect(res.body.transaction).toBeDefined();
    });

    it('POST /api/execution/:strategyId should return 422 if validation fails', async () => {
      (contracts.dcaEngine.getStrategy as any).mockResolvedValue({
        owner: '0x123', inputToken: '0xabc', targetToken: '0xdef',
        targetAllocation: 1000n, frequency: 86400n, maxDelay: 3600n,
        minExecutionAmount: 10n, maxExecutionAmount: 100n, nextExecutionTime: 0n, status: 1
      });
      (contracts.executionManager.getExecutionRecord as any).mockResolvedValue({
        lastExecutionTimestamp: 0n, lastExecutionAmount: 0n, totalExecuted: 0n, nonce: 0n
      });
      (contracts.decisionEngine.evaluate as any).mockResolvedValue({
        action: 1n, targetAmount: 100n, executionAmount: 10n, remainingAmount: 90n,
        recommendedDelay: 0n, score: 50n, reason: "test", timestamp: 0n, diagnostics: {}
      });
      (contracts.marketAnalyzer["getMarketState()"] as any).mockResolvedValue({});
      (contracts.yieldVault.balanceOf as any).mockResolvedValue(100n);
      (contracts.yieldVault.convertToAssets as any).mockResolvedValue(100n);
      (contracts.dcaEngine.getRemainingDelay as any).mockResolvedValue(0n);
      (contracts.yieldAnalyzer.analyzeYieldOpportunity as any).mockResolvedValue({});
      
      (contracts.executionManager.validateExecution as any).mockRejectedValue(new Error("validation reverted"));

      const res = await request(app).post('/api/execution/1');
      expect(res.status).toBe(422);
    });
  });

});
