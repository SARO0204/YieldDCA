import { getActiveStrategies, getStrategyState } from './strategy.service';
import { getMarketState } from './market.service';
import { getYieldAnalysisForStrategy } from './yield.service';
import { getDecision } from './decision.service';
import { prepareExecution } from './execution.service';
import { upsertSchedulerJob, getSchedulerJob, insertDecisionHistory } from '../db/database';
import crypto from 'crypto';
import { loadConfig } from '../config';

const config = loadConfig();

interface SchedulerStatus {
  enabled: boolean;
  running: boolean;
  lastRunAt: string | null;
  nextRunAt: string | null;
  lastRunDuration: number;
  jobsProcessed: number;
  jobsSucceeded: number;
  jobsDelayed: number;
  jobsPrepared: number;
  jobsFailed: number;
}

let intervalId: NodeJS.Timeout | null = null;
let isProcessing = false;

const status: SchedulerStatus = {
  enabled: config.scheduler.enabled,
  running: false,
  lastRunAt: null,
  nextRunAt: null,
  lastRunDuration: 0,
  jobsProcessed: 0,
  jobsSucceeded: 0,
  jobsDelayed: 0,
  jobsPrepared: 0,
  jobsFailed: 0,
};

// In-memory locks to prevent concurrent evaluation of the same strategy
const processingStrategies = new Set<string>();

export function getSchedulerStatus() {
  return status;
}

export function startScheduler() {
  if (intervalId) return;
  status.running = true;
  console.log(`[Scheduler] Starting scheduler. Interval: ${config.scheduler.intervalMs}ms`);
  intervalId = setInterval(() => {
    runOnce().catch(err => console.error('[Scheduler] runOnce failed:', err));
  }, config.scheduler.intervalMs);
  
  // Set nextRunAt immediately
  status.nextRunAt = new Date(Date.now() + config.scheduler.intervalMs).toISOString();
}

export function stopScheduler() {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
  status.running = false;
  status.nextRunAt = null;
  console.log('[Scheduler] Stopped.');
}

function calculateNextEvaluation(lastExec: bigint, frequency: bigint): number {
  if (lastExec === 0n) return Math.floor(Date.now() / 1000);
  return Number(lastExec + frequency);
}

function generateJobId(strategyId: string, nextEvalTimestamp: number): string {
  return crypto.createHash('sha256').update(`${strategyId}-${nextEvalTimestamp}`).digest('hex');
}

export async function runOnce() {
  if (isProcessing) {
    console.log('[Scheduler] Already processing a cycle. Skipping.');
    return;
  }

  isProcessing = true;
  const startTime = Date.now();
  status.lastRunAt = new Date().toISOString();

  try {
    const strategies = await getActiveStrategies();

    for (const stratId of strategies) {
      if (processingStrategies.has(stratId)) continue;
      
      try {
        processingStrategies.add(stratId);
        await processStrategy(stratId);
      } catch (err: any) {
        console.error(`[Scheduler] Error processing strategy ${stratId}:`, err.message);
      } finally {
        processingStrategies.delete(stratId);
      }
    }
  } catch (err: any) {
    console.error('[Scheduler] Error discovering strategies:', err.message);
  } finally {
    isProcessing = false;
    status.lastRunDuration = Date.now() - startTime;
    if (status.running) {
      status.nextRunAt = new Date(Date.now() + config.scheduler.intervalMs).toISOString();
    }
  }
}

async function processStrategy(strategyId: string) {
  // Load strategy
  const strat = await getStrategyState(strategyId);

  // Skip inactive (status 1 is ACTIVE)
  if (strat.status !== 1) return;
  
  // Skip if zero allocation remaining
  const remainingAlloc = BigInt(strat.targetAllocation) - BigInt(strat.record.totalExecuted);
  if (remainingAlloc <= 0n) return;

  const now = Math.floor(Date.now() / 1000);
  const nextEval = calculateNextEvaluation(BigInt(strat.record.lastExecutionTimestamp), BigInt(strat.frequency));
  const currentDelay = now - nextEval;
  const maxDelay = Number(strat.maxDelay);

  // Not due yet
  if (now < nextEval) return;

  const jobId = generateJobId(strategyId, nextEval);
  let job = getSchedulerJob(jobId);

  if (job) {
    if (job.status === 'COMPLETED' || job.status === 'PREPARED') return; // Idempotency
    if (job.status === 'PROCESSING') return;
    if (job.status === 'FAILED') {
      if (job.attemptCount >= config.scheduler.maxRetries) return; // Retry limit
      if (job.nextRetryAt && now < job.nextRetryAt) return; // Wait for retry
    }
  } else {
    job = {
      jobId,
      strategyId,
      scheduledAt: nextEval,
      status: 'PROCESSING',
      attemptCount: 0,
      createdAt: new Date().toISOString()
    };
  }

  job.status = 'PROCESSING';
  job.attemptCount += 1;
  upsertSchedulerJob(job);
  status.jobsProcessed++;

  try {
    const marketState = await getMarketState(strategyId);
    const yieldState = await getYieldAnalysisForStrategy(strategyId);
    
    // Evaluate Decision
    const decision: any = await getDecision(strategyId);

    // Hard Boundary: Maximum Delay
    let actionToTake = decision.action;
    let enforceMaxDelay = false;
    
    // If it's a delay, check bounds
    if (actionToTake === 0 && currentDelay >= maxDelay) {
      // Force evaluate with strict conditions
      // In this system, max delay forces a market evaluation ignoring some yield metrics, but DecisionEngine might handle it.
      // For this MVP bounded scheduler, if DecisionEngine still outputs DELAY but currentDelay >= maxDelay, 
      // we must prepare execution to adhere to the hard boundary unless remaining limits prevent it.
      console.warn(`[Scheduler] Strategy ${strategyId} reached maximum delay (${currentDelay}s >= ${maxDelay}s). Overriding DELAY to EXECUTE.`);
      actionToTake = 1; // EXECUTE
      enforceMaxDelay = true;
    }

    job.decision = actionToTake;
    job.recommendedDelay = decision.recommendedDelay;

    if (actionToTake === 0) { // DELAY
      job.status = 'DELAYED';
      job.reason = enforceMaxDelay ? "Max delay reached, but fallback to DELAY (unexpected)" : (decision.reason || "Decision engine recommended delay.");
      insertDecisionHistory({
        jobId,
        strategyId,
        action: 'DELAY',
        reason: job.reason,
        currentDelay,
        maxDelay
      });
      upsertSchedulerJob(job);
      status.jobsDelayed++;
      return;
    }

    // EXECUTE or PARTIAL_EXECUTION
    let execAmount = BigInt(decision.executionAmount);
    
    // Safety check against minimum/maximum (already done in DecisionEngine, but we re-verify bounds here to be strictly safe)
    if (execAmount < BigInt(strat.minExecutionAmount)) {
       throw new Error(`Execution amount ${execAmount} below minimum ${strat.minExecutionAmount}`);
    }
    if (execAmount > BigInt(strat.maxExecutionAmount)) {
       execAmount = BigInt(strat.maxExecutionAmount);
    }
    if (execAmount > remainingAlloc) {
       execAmount = remainingAlloc;
    }

    // Prepare transaction via ExecutionManager
    const tx = await prepareExecution(strategyId, execAmount.toString(), strat.record.nonce.toString());
    
    job.status = 'PREPARED';
    job.executionAmount = execAmount.toString();
    job.transaction = tx; // Prepared payload (target, data, value)
    
    upsertSchedulerJob(job);
    status.jobsPrepared++;
    status.jobsSucceeded++;

  } catch (err: any) {
    job.status = 'FAILED';
    job.error = err.message || String(err);
    // Determine retryability (rough heuristic for MVP: if it's a validation error, don't retry)
    const nonRetryable = ['below minimum', 'exceeds', 'unauthorized', 'reverted'].some(term => job.error.toLowerCase().includes(term));
    if (!nonRetryable) {
      job.nextRetryAt = Math.floor(Date.now() / 1000) + 30; // 30s delay
    } else {
      job.attemptCount = config.scheduler.maxRetries; // Force stop retries
    }
    upsertSchedulerJob(job);
    status.jobsFailed++;
  }
}
