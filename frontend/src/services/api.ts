// Simple types matching the backend endpoints
export interface DashboardData {
  vault: {
    totalAssets: string;
    totalShares: string;
    simulatedAPY: string;
    user: { assets: string; shares: string } | null;
  };
  market: {
    currentPrice: string;
    twap: string;
    priceDeviation: string;
    volatility: string;
    liquidity: string;
    estimatedSlippage: string;
    estimatedPriceImpact: string;
    timestamp: string;
    dataSource: string;
  };
  yield: {
    currentAPY: string;
    principalAssets: string;
    projectedYield7D: string;
    projectedYield30D: string;
    projectedYield365D: string;
  };
  strategy: any | null;
}

const API_BASE = 'http://localhost:3000/api';

export async function fetchDashboard(userAddress?: string, strategyId?: string): Promise<DashboardData> {
  const url = new URL(`${API_BASE}/dashboard`);
  if (userAddress) url.searchParams.append('user', userAddress);
  if (strategyId) url.searchParams.append('strategy', strategyId);

  const res = await fetch(url.toString());
  if (!res.ok) throw new Error('Failed to fetch dashboard data');
  return res.json();
}
