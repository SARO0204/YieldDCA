import path from 'path';
import fs from 'fs';

const DB_DIR = path.join(__dirname, '../../data');
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

const dbPath = path.join(DB_DIR, 'db.json');

function readDb() {
  if (!fs.existsSync(dbPath)) {
    return { historical_market: [], historical_yield: [] };
  }
  return JSON.parse(fs.readFileSync(dbPath, 'utf8'));
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
