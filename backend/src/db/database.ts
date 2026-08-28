import path from 'path';
import fs from 'fs';

const DB_DIR = path.join(__dirname, '../../data');
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

const dbPath = path.join(DB_DIR, 'db.json');

function readDb() {
  if (!fs.existsSync(dbPath)) {
    return { historical_market: [], historical_yield: [], executions: [], scheduler_jobs: [], decision_history: [] };
  }
  const db = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
  if (!db.executions) db.executions = [];
  if (!db.scheduler_jobs) db.scheduler_jobs = [];
  if (!db.decision_history) db.decision_history = [];
  return db;
}

function writeDb(data: any) {
  fs.writeFileSync(dbPath, JSON.stringify(data, null, 2));
}

export function insertMarketSnapshot(marketState: any) {
  const db = readDb();
  db.historical_market.push({
    current_price: marketState.currentPrice,
    twap: marketState.twap,
    volatility: marketState.volatility,
    liquidity: marketState.liquidity,
    timestamp: marketState.timestamp,
    created_at: new Date().toISOString()
  });
  writeDb(db);
}

export function insertYieldSnapshot(vaultState: any) {
  const db = readDb();
  db.historical_yield.push({
    simulated_apy: vaultState.simulatedAPY,
    total_assets: vaultState.totalAssets,
    timestamp: Math.floor(Date.now() / 1000),
    created_at: new Date().toISOString()
  });
  writeDb(db);
}

export function insertExecutionRecord(execution: any) {
  const db = readDb();
  db.executions.push({
    ...execution,
    created_at: new Date().toISOString()
  });
  writeDb(db);
}

export function getExecutionHistory(strategyId: string | number) {
  const db = readDb();
  return db.executions.filter((e: any) => String(e.strategyId) === String(strategyId));
}

// Module 11 Scheduler & Decision persistence
export function getSchedulerJob(jobId: string) {
  const db = readDb();
  return db.scheduler_jobs.find((j: any) => j.jobId === jobId);
}

export function getAllSchedulerJobs() {
  const db = readDb();
  return db.scheduler_jobs;
}

export function upsertSchedulerJob(job: any) {
  const db = readDb();
  const idx = db.scheduler_jobs.findIndex((j: any) => j.jobId === job.jobId);
  if (idx >= 0) {
    db.scheduler_jobs[idx] = { ...db.scheduler_jobs[idx], ...job, updated_at: new Date().toISOString() };
  } else {
    db.scheduler_jobs.push({ ...job, created_at: new Date().toISOString(), updated_at: new Date().toISOString() });
  }
  writeDb(db);
}

export function insertDecisionHistory(decision: any) {
  const db = readDb();
  db.decision_history.push({
    ...decision,
    created_at: new Date().toISOString()
  });
  writeDb(db);
}

