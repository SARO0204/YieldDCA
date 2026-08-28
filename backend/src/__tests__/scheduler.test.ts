import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runOnce, startScheduler, stopScheduler, getSchedulerStatus } from '../services/scheduler.service';
import * as strategyService from '../services/strategy.service';
import * as marketService from '../services/market.service';
import * as yieldService from '../services/yield.service';
import * as decisionService from '../services/decision.service';
import * as executionService from '../services/execution.service';
import * as database from '../db/database';

vi.mock('../services/strategy.service');
vi.mock('../services/market.service');
vi.mock('../services/yield.service');
vi.mock('../services/decision.service');
vi.mock('../services/execution.service');
vi.mock('../db/database');
vi.mock('../config', () => ({
  loadConfig: () => ({
    scheduler: {
      enabled: true,
      intervalMs: 100,
      maxRetries: 3
    },
    contracts: {
      dcaEngine: '0x1',
      yieldVault: '0x1',
      marketAnalyzer: '0x1',
      yieldAnalyzer: '0x1',
      mockErc20: '0x1',
      decisionEngine: '0x1',
      executionManager: '0x1',
      mockSwapExecutor: '0x1'
    }
  })
}));

import { runOnce, startScheduler, stopScheduler, getSchedulerStatus } from '../services/scheduler.service';

describe('Bounded DCA Automation Scheduler', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(1000000000000)); // Timestamp: 1000000000 (s)
    
    // Default Mocks
    vi.mocked(strategyService.getActiveStrategies).mockResolvedValue(['1']);
    vi.mocked(strategyService.getStrategyState).mockResolvedValue({
      status: 1, // ACTIVE
      targetAllocation: '10000',
      frequency: '3600', // 1 hour
      maxDelay: '86400', // 1 day
      minExecutionAmount: '100',
      maxExecutionAmount: '1000',
      record: {
        totalExecuted: '0',
        lastExecutionTimestamp: '999996400', // 1 hour ago -> due now
        nonce: '1'
      }
    } as any);

    vi.mocked(marketService.getMarketState).mockResolvedValue({} as any);
    vi.mocked(yieldService.getYieldAnalysisForStrategy).mockResolvedValue({} as any);
    
    vi.mocked(decisionService.getDecision).mockResolvedValue({
      action: 1, // EXECUTE
      executionAmount: '500',
      recommendedDelay: '0',
      reason: 'Good'
    } as any);

    vi.mocked(executionService.prepareExecution).mockResolvedValue({
      to: '0x123',
      data: '0xabc',
      value: '0'
    } as any);
    
    vi.mocked(database.getSchedulerJob).mockReturnValue(undefined);
    vi.mocked(database.upsertSchedulerJob).mockImplementation(() => {});
    vi.mocked(database.insertDecisionHistory).mockImplementation(() => {});
  });

  afterEach(() => {
    stopScheduler();
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('22. runOnce() processes one cycle and creates a job', async () => {
    await runOnce();
    expect(strategyService.getActiveStrategies).toHaveBeenCalled();
    expect(database.upsertSchedulerJob).toHaveBeenCalled();
    const status = getSchedulerStatus();
    expect(status.jobsProcessed).toBe(1);
    expect(status.jobsPrepared).toBe(1);
  });

  it('19. scheduler start and 20. stop', () => {
    startScheduler();
    expect(getSchedulerStatus().running).toBe(true);
    stopScheduler();
    expect(getSchedulerStatus().running).toBe(false);
  });

  it('21. start() called twice does not create duplicate intervals', () => {
    const spy = vi.spyOn(global, 'setInterval');
    startScheduler();
    startScheduler();
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('2. not-yet-due strategy is skipped', async () => {
    vi.mocked(strategyService.getStrategyState).mockResolvedValueOnce({
      status: 1,
      targetAllocation: '10000',
      frequency: '3600',
      maxDelay: '86400',
      record: {
        totalExecuted: '0',
        lastExecutionTimestamp: '999998200', // 30 mins ago -> not due
        nonce: '1'
      }
    } as any);
    await runOnce();
    expect(decisionService.getDecision).not.toHaveBeenCalled();
  });

  it('8. completed strategy skipped', async () => {
    vi.mocked(strategyService.getStrategyState).mockResolvedValueOnce({
      status: 4, // COMPLETED
    } as any);
    await runOnce();
    expect(decisionService.getDecision).not.toHaveBeenCalled();
  });

  it('9. paused strategy skipped', async () => {
    vi.mocked(strategyService.getStrategyState).mockResolvedValueOnce({
      status: 2, // PAUSED
    } as any);
    await runOnce();
    expect(decisionService.getDecision).not.toHaveBeenCalled();
  });

  it('10. zero remaining allocation skipped', async () => {
    vi.mocked(strategyService.getStrategyState).mockResolvedValueOnce({
      status: 1,
      targetAllocation: '10000',
      record: {
        totalExecuted: '10000'
      }
    } as any);
    await runOnce();
    expect(decisionService.getDecision).not.toHaveBeenCalled();
  });

  it('3. DELAY decision is recorded and execution is not prepared', async () => {
    vi.mocked(decisionService.getDecision).mockResolvedValueOnce({
      action: 0, // DELAY
      executionAmount: '0',
      recommendedDelay: '3600',
      reason: 'Wait'
    } as any);
    await runOnce();
    expect(database.insertDecisionHistory).toHaveBeenCalled();
    expect(executionService.prepareExecution).not.toHaveBeenCalled();
  });

  it('4. maximum delay reached and 5. maximum delay boundary override', async () => {
    vi.mocked(strategyService.getStrategyState).mockResolvedValueOnce({
      status: 1,
      targetAllocation: '10000',
      frequency: '3600',
      maxDelay: '3600', // max delay is 1 hour
      minExecutionAmount: '10',
      maxExecutionAmount: '1000',
      record: {
        totalExecuted: '0',
        lastExecutionTimestamp: '999992800', // 2 hours ago -> max delay reached
        nonce: '1'
      }
    } as any);
    
    // Engine says DELAY
    vi.mocked(decisionService.getDecision).mockResolvedValueOnce({
      action: 0,
      executionAmount: '500',
      recommendedDelay: '3600',
      reason: 'Wait'
    } as any);

    await runOnce();
    // It should force EXECUTE
    expect(executionService.prepareExecution).toHaveBeenCalled();
  });

  it('11. duplicate job prevention / 12. duplicate runOnce prevention', async () => {
    vi.mocked(database.getSchedulerJob).mockReturnValue({
      status: 'PREPARED'
    } as any);
    
    await runOnce();
    
    // Should skip since job exists and is prepared
    expect(decisionService.getDecision).not.toHaveBeenCalled();
  });

  it('14. transient failure retry', async () => {
    vi.mocked(executionService.prepareExecution).mockRejectedValueOnce(new Error("RPC failed"));
    await runOnce();
    
    expect(database.upsertSchedulerJob).toHaveBeenCalledWith(expect.objectContaining({
      status: 'FAILED',
      error: 'RPC failed'
    }));
    
    const upsertedCall = vi.mocked(database.upsertSchedulerJob).mock.calls.find(call => call[0].status === 'FAILED');
    expect(upsertedCall![0].nextRetryAt).toBeDefined();
  });

  it('16. permanent failure not retried indefinitely', async () => {
    vi.mocked(executionService.prepareExecution).mockRejectedValueOnce(new Error("execution reverted"));
    await runOnce();
    
    const upsertedCall = vi.mocked(database.upsertSchedulerJob).mock.calls.find(call => call[0].status === 'FAILED');
    // Permanent failures max out attempts
    expect(upsertedCall![0].attemptCount).toBe(3); 
    expect(upsertedCall![0].nextRetryAt).toBeUndefined();
  });

  it('25. scheduler never increases DecisionEngine executionAmount', async () => {
    vi.mocked(decisionService.getDecision).mockResolvedValueOnce({
      action: 1,
      executionAmount: '5000', // Engine wants to execute 5000
    } as any);
    
    // But strategy max is 1000
    await runOnce();
    expect(executionService.prepareExecution).toHaveBeenCalledWith('1', '1000', '1');
  });
  
  it('bounds minimum execution check', async () => {
    vi.mocked(decisionService.getDecision).mockResolvedValueOnce({
      action: 1,
      executionAmount: '50', // Engine wants 50
    } as any);
    
    // Strategy min is 100
    await runOnce();
    const upsertedCall = vi.mocked(database.upsertSchedulerJob).mock.calls.find(call => call[0].status === 'FAILED');
    expect(upsertedCall).toBeDefined();
    expect(upsertedCall![0].error).toContain('below minimum');
  });
});
