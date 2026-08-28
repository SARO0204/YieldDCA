import React, { useEffect, useState } from 'react';
import { useWallet } from '../hooks/useWallet';
import { fetchDashboard, fetchExecutionHistory, type DashboardData } from '../services/api';
import { Wallet, Activity, RefreshCw, AlertCircle, Shield, Target } from 'lucide-react';
import { ethers } from 'ethers';
import { VaultActions } from '../components/VaultActions';
import { StrategyActions } from '../components/StrategyActions';
import { DecisionPanel } from '../components/DecisionPanel';
import { ExecutionHistory } from '../components/ExecutionHistory';
import { DemoPanel } from '../components/DemoPanel';

const Dashboard: React.FC = () => {
  const { address, connect, disconnect, error: walletError } = useWallet();
  const [data, setData] = useState<DashboardData | null>(null);
  const [history, setHistory] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [schedulerStatus, setSchedulerStatus] = useState<any>(null);

  const loadData = async () => {
    setLoading(true);
    try {
      const res = await fetchDashboard(address || undefined, "1"); // Assuming strategy ID 1 for now
      setData(res);
      
      const historyRes = await fetchExecutionHistory("1");
      setHistory(historyRes.history || []);

      try {
        const sStatus = await import('../services/api').then(m => m.fetchSchedulerStatus());
        setSchedulerStatus(sStatus);
      } catch (e) {
        // ignore if backend doesn't support scheduler yet
      }
      
      setError(null);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
    const intv = setInterval(loadData, 10000);
    return () => clearInterval(intv);
  }, [address]);

  const formatUnits = (val: string, dec = 18) => {
    try {
      return parseFloat(ethers.formatUnits(val, dec)).toFixed(4);
    } catch {
      return "0.0000";
    }
  };

  return (
    <div className="min-h-screen p-8 max-w-7xl mx-auto pb-20">
      <header className="flex justify-between items-center mb-10 border-b border-slate-700 pb-6">
        <div>
          <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-indigo-500 flex items-center gap-3">
            Yield-Aware DCA
            <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">Local Anvil Demo</span>
          </h1>
          <p className="text-slate-400 mt-1">Intelligent capital allocation</p>
        </div>

        <div className="flex items-center gap-4">
          <button onClick={loadData} className="p-2 bg-slate-800 rounded-full hover:bg-slate-700 transition">
            <RefreshCw size={20} className={loading ? "animate-spin text-blue-400" : "text-slate-300"} />
          </button>
          
          {address ? (
            <button onClick={disconnect} className="flex items-center gap-2 px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded-lg font-medium transition text-sm border border-slate-600">
              <div className="w-2 h-2 rounded-full bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.6)]"></div>
              {address.substring(0,6)}...{address.substring(address.length - 4)}
            </button>
          ) : (
            <button onClick={connect} className="flex items-center gap-2 px-6 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg font-medium transition shadow-lg shadow-indigo-600/20">
              <Wallet size={18} />
              Connect Wallet
            </button>
          )}
        </div>
      </header>

      {(walletError || error) && (
        <div className="mb-8 p-4 bg-red-900/40 border border-red-500/50 rounded-lg flex items-center gap-3 text-red-200">
          <AlertCircle size={20} className="shrink-0" />
          <p>{walletError || error}</p>
        </div>
      )}

      {loading && !data && (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-indigo-500"></div>
        </div>
      )}

      {data && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">

          <DemoPanel strategyId="1" onUpdate={loadData} />

          {/* Automation Status */}
          {schedulerStatus && (
            <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm lg:col-span-3">
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-semibold flex items-center gap-2">Automation Scheduler</h2>
                <span className={`px-3 py-1 rounded text-xs font-bold ${schedulerStatus.running ? 'bg-green-500/20 text-green-400 border border-green-500/30' : 'bg-slate-700 text-slate-400'}`}>
                  {schedulerStatus.running ? 'ENABLED & RUNNING' : 'DISABLED'}
                </span>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <span className="text-slate-400 block mb-1">Last Run</span>
                  <span className="text-white">{schedulerStatus.lastRunAt ? new Date(schedulerStatus.lastRunAt).toLocaleString() : 'Never'}</span>
                </div>
                <div>
                  <span className="text-slate-400 block mb-1">Next Run</span>
                  <span className="text-white">{schedulerStatus.nextRunAt ? new Date(schedulerStatus.nextRunAt).toLocaleString() : 'N/A'}</span>
                </div>
                <div>
                  <span className="text-slate-400 block mb-1">Processed Jobs</span>
                  <span className="text-white font-medium">{schedulerStatus.jobsProcessed}</span>
                </div>
                <div className="flex gap-4">
                  <div>
                    <span className="text-slate-400 block mb-1">Prepared</span>
                    <span className="text-green-400 font-medium">{schedulerStatus.jobsPrepared}</span>
                  </div>
                  <div>
                    <span className="text-slate-400 block mb-1">Delayed</span>
                    <span className="text-blue-400 font-medium">{schedulerStatus.jobsDelayed}</span>
                  </div>
                  <div>
                    <span className="text-slate-400 block mb-1">Failed</span>
                    <span className="text-red-400 font-medium">{schedulerStatus.jobsFailed}</span>
                  </div>
                </div>
              </div>
            </div>
          )}
          
          {/* Strategy Panel */}
          <div className="lg:col-span-1">
            <StrategyActions strategy={data.strategy} onUpdate={loadData} />
          </div>

          {/* Vault Panel */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm lg:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <div className="flex items-center gap-3 mb-6">
                <div className="p-2 bg-blue-500/20 rounded-lg text-blue-400"><Shield size={24}/></div>
                <h2 className="text-xl font-semibold flex items-center gap-2">Yield Vault <span className="text-[10px] uppercase bg-slate-700 px-2 py-0.5 rounded text-slate-300">Mock USDC</span></h2>
              </div>
              
              <div className="space-y-4">
                <div className="flex justify-between">
                  <span className="text-slate-400">Total Vault TVL</span>
                  <span className="font-medium text-white">{formatUnits(data.vault.totalAssets, 6)} USDC</span>
                </div>
                <div className="flex justify-between pt-3 border-t border-slate-700/50">
                  <span className="text-slate-400">Simulated APY</span>
                  <span className="font-bold text-green-400">{(Number(data.vault.simulatedAPY) / 100).toFixed(2)}%</span>
                </div>
                
                {data.vault.user && (
                  <div className="mt-6 p-4 bg-slate-900/50 rounded-lg border border-slate-700">
                    <h3 className="text-sm font-semibold text-slate-300 mb-2 uppercase tracking-wider">Your Position</h3>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-slate-400">Deposited Assets</span>
                      <span className="text-white font-medium">{formatUnits(data.vault.user.assets, 6)} USDC</span>
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-slate-400">Vault Shares</span>
                      <span className="text-white">{formatUnits(data.vault.user.shares, 18)}</span>
                    </div>
                  </div>
                )}
              </div>
            </div>
            
            <div className="border-t md:border-t-0 md:border-l border-slate-700/50 pt-6 md:pt-0 md:pl-6 flex flex-col justify-between">
              <VaultActions />
            </div>
          </div>

          {/* Market Intelligence */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm lg:col-span-2">
             <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-purple-500/20 rounded-lg text-purple-400"><Target size={24}/></div>
              <h2 className="text-xl font-semibold flex items-center gap-2">Market Analysis <span className="text-[10px] uppercase bg-slate-700 px-2 py-0.5 rounded text-slate-300">Mock Data</span></h2>
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div className="flex justify-between">
                  <span className="text-slate-400">Current Price</span>
                  <span className="font-medium text-white">${formatUnits(data.market.currentPrice, 18)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">TWAP (Oracle)</span>
                  <span className="font-medium text-white">${formatUnits(data.market.twap, 18)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Price Deviation</span>
                  <span className={`font-medium ${Number(data.market.priceDeviation) >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                     {Number(data.market.priceDeviation) > 0 ? '+' : ''}{formatUnits(data.market.priceDeviation, 18)}
                  </span>
                </div>
              </div>
              <div className="space-y-4">
                <div className="flex justify-between">
                  <span className="text-slate-400">Volatility</span>
                  <span className="text-white">{(Number(data.market.volatility) / 1e16).toFixed(2)}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Liquidity Depth</span>
                  <span className="text-white">{formatUnits(data.market.liquidity, 18)} ETH</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Est. Slippage</span>
                  <span className="text-white">{(Number(data.market.estimatedSlippage) / 1e16).toFixed(4)}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Price Impact</span>
                  <span className="text-white">{(Number(data.market.estimatedPriceImpact) / 1e16).toFixed(4)}%</span>
                </div>
              </div>
            </div>
          </div>

          {/* Yield Projections */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
             <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-green-500/20 rounded-lg text-green-400"><Activity size={24}/></div>
              <h2 className="text-xl font-semibold flex items-center gap-2">Yield Analysis</h2>
            </div>
            
            <div className="space-y-4">
               <div className="flex justify-between">
                <span className="text-slate-400">Current APY</span>
                <span className="font-medium text-green-400">{(Number(data.yield.currentAPY) / 100).toFixed(2)}%</span>
              </div>
              <div className="flex justify-between pt-3 border-t border-slate-700/50">
                <span className="text-slate-400">Estimated Waiting Yield</span>
                <span className="font-medium text-green-400">+{formatUnits(data.yield.estimatedWaitingYield, 6)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Opportunity Cost</span>
                <span className="font-medium text-red-400">-{formatUnits(data.yield.opportunityCost, 6)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Waiting Benefit</span>
                <span className="font-medium text-blue-400">{formatUnits(data.yield.waitingBenefit, 6)} USDC</span>
              </div>
              <div className="flex justify-between pt-3 border-t border-slate-700/50">
                <span className="text-slate-400">Urgency</span>
                <span className="font-bold text-white">{(Number(data.yield.urgency) / 100).toFixed(2)}%</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Recommendation</span>
                <span className="font-bold text-white">{data.yield.recommendation === 1 ? 'EXECUTE' : data.yield.recommendation === 2 ? 'PARTIAL' : 'WAIT'}</span>
              </div>
            </div>
          </div>

          <DecisionPanel strategy={data.strategy} onUpdate={loadData} />
          
          <div className="lg:col-span-3">
            <ExecutionHistory history={history} />
          </div>

        </div>
      )}
    </div>
  );
};

export default Dashboard;
