import React, { useEffect, useState } from 'react';
import { useWallet } from '../hooks/useWallet';
import { fetchDashboard, type DashboardData } from '../services/api';
import { Wallet, Activity, RefreshCw, AlertCircle, Shield, Target } from 'lucide-react';
import { ethers } from 'ethers';

const Dashboard: React.FC = () => {
  const { address, connect, disconnect, error: walletError } = useWallet();
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadData = async () => {
    setLoading(true);
    try {
      const res = await fetchDashboard(address || undefined);
      setData(res);
      setError(null);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
    // Auto refresh every 10s
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
    <div className="min-h-screen p-8 max-w-7xl mx-auto">
      <header className="flex justify-between items-center mb-10 border-b border-slate-700 pb-6">
        <div>
          <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-indigo-500">
            Yield-Aware DCA
          </h1>
          <p className="text-slate-400 mt-1">Intelligent capital allocation</p>
        </div>

        <div className="flex items-center gap-4">
          <button onClick={loadData} className="p-2 bg-slate-800 rounded-full hover:bg-slate-700 transition">
            <RefreshCw size={20} className={loading ? "animate-spin text-blue-400" : "text-slate-300"} />
          </button>
          
          {address ? (
            <button onClick={disconnect} className="flex items-center gap-2 px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded-lg font-medium transition text-sm">
              <div className="w-2 h-2 rounded-full bg-green-500"></div>
              {address.substring(0,6)}...{address.substring(address.length - 4)}
            </button>
          ) : (
            <button onClick={connect} className="flex items-center gap-2 px-6 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg font-medium transition">
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
          
          {/* Vault Panel */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
            <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-blue-500/20 rounded-lg text-blue-400"><Shield size={24}/></div>
              <h2 className="text-xl font-semibold">Yield Vault</h2>
            </div>
            
            <div className="space-y-4">
              <div className="flex justify-between">
                <span className="text-slate-400">Total Assets</span>
                <span className="font-medium text-white">{formatUnits(data.vault.totalAssets, 6)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Total Shares</span>
                <span className="font-medium text-white">{formatUnits(data.vault.totalShares, 18)}</span>
              </div>
              <div className="flex justify-between pt-3 border-t border-slate-700/50">
                <span className="text-slate-400">Simulated APY</span>
                <span className="font-bold text-green-400">{(Number(data.vault.simulatedAPY) / 100).toFixed(2)}%</span>
              </div>
              
              {data.vault.user && (
                <div className="mt-6 p-4 bg-slate-900/50 rounded-lg border border-slate-700">
                  <h3 className="text-sm font-semibold text-slate-300 mb-2 uppercase tracking-wider">Your Position</h3>
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-400">Assets</span>
                    <span className="text-white">{formatUnits(data.vault.user.assets, 6)} USDC</span>
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Yield Projections */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
             <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-green-500/20 rounded-lg text-green-400"><Activity size={24}/></div>
              <h2 className="text-xl font-semibold">Yield Projections</h2>
            </div>
            
            <div className="space-y-4">
               <div className="flex justify-between">
                <span className="text-slate-400">Base Principal</span>
                <span className="font-medium text-white">{formatUnits(data.yield.principalAssets, 6)} USDC</span>
              </div>
              <div className="flex justify-between pt-3 border-t border-slate-700/50">
                <span className="text-slate-400">7-Day Yield</span>
                <span className="font-medium text-green-400">+{formatUnits(data.yield.projectedYield7D, 6)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">30-Day Yield</span>
                <span className="font-medium text-green-400">+{formatUnits(data.yield.projectedYield30D, 6)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">1-Year Yield</span>
                <span className="font-medium text-green-400">+{formatUnits(data.yield.projectedYield365D, 6)}</span>
              </div>
            </div>
          </div>

          {/* Market Intelligence */}
          <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
             <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-purple-500/20 rounded-lg text-purple-400"><Target size={24}/></div>
              <h2 className="text-xl font-semibold">Market Analysis</h2>
            </div>
            
            <div className="space-y-4">
              <div className="flex justify-between">
                <span className="text-slate-400">Asset Price</span>
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
              <div className="flex justify-between pt-3 border-t border-slate-700/50">
                <span className="text-slate-400">Volatility</span>
                <span className="text-white">{(Number(data.market.volatility) / 1e16).toFixed(2)}%</span>
              </div>
            </div>
          </div>
          
        </div>
      )}
    </div>
  );
};

export default Dashboard;
