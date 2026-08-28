import React, { useState } from 'react';
import { ethers } from 'ethers';
import { useWallet } from '../hooks/useWallet';
import { createStrategy, pauseStrategy, resumeStrategy, cancelStrategy } from '../services/transactions';
import { Loader2, Pause, Play, XOctagon } from 'lucide-react';
import { addresses } from '../contracts/config';

interface Props {
  strategy: any | null;
  onUpdate: () => void;
}

export const StrategyActions: React.FC<Props> = ({ strategy, onUpdate }) => {
  const { provider } = useWallet();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form states for creating strategy
  const [amount, setAmount] = useState('1000');
  const [freq, setFreq] = useState('86400'); // 1 day

  const handleAction = async (action: 'pause' | 'resume' | 'cancel', strategyId: string) => {
    if (!provider) return;
    setLoading(true);
    setError(null);
    try {
      if (action === 'pause') await pauseStrategy(provider, strategyId);
      if (action === 'resume') await resumeStrategy(provider, strategyId);
      if (action === 'cancel') await cancelStrategy(provider, strategyId);
      onUpdate();
    } catch (err: any) {
      setError(err.reason || err.message || 'Action failed');
    } finally {
      setLoading(false);
    }
  };

  const handleCreate = async () => {
    if (!provider) return;
    setLoading(true);
    setError(null);
    try {
      const targetAllocation = ethers.parseUnits(amount, 6);
      
      const params = {
        inputToken: addresses.mockErc20,
        targetToken: "0x0000000000000000000000000000000000000001", // Example WETH target
        targetAllocation: targetAllocation.toString(),
        frequency: freq,
        maxDelay: "3600", // 1 hour
        minExecutionAmount: ethers.parseUnits("10", 6).toString(),
        maxExecutionAmount: targetAllocation.toString(),
        firstExecutionTime: "0" // Starts immediately
      };
      
      await createStrategy(provider, params);
      onUpdate();
    } catch (err: any) {
      setError(err.reason || err.message || 'Creation failed');
    } finally {
      setLoading(false);
    }
  };

  const getStatusString = (statusId: number) => {
    const states = ['NONE', 'ACTIVE', 'PAUSED', 'CANCELLED', 'COMPLETED'];
    return states[statusId] || 'UNKNOWN';
  };

  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm h-full">
      <div className="flex items-center gap-3 mb-6">
        <h2 className="text-xl font-semibold">DCA Strategy</h2>
      </div>

      {error && <div className="mb-4 text-sm text-red-400 p-3 bg-red-900/20 rounded">{error}</div>}

      {strategy ? (
        <div className="space-y-4">
          <div className="flex justify-between items-center p-3 bg-slate-900/50 rounded-lg border border-slate-700">
            <div>
              <div className="text-slate-400 text-sm">Status</div>
              <div className="font-bold text-white">{getStatusString(strategy.status)}</div>
            </div>
            
            <div className="flex gap-2">
              {strategy.status === 1 && ( // ACTIVE
                <button 
                  onClick={() => handleAction('pause', '1')} 
                  disabled={loading}
                  className="p-2 bg-yellow-600/20 text-yellow-500 hover:bg-yellow-600/40 rounded transition"
                  title="Pause"
                >
                  <Pause size={18} />
                </button>
              )}
              {strategy.status === 2 && ( // PAUSED
                <button 
                  onClick={() => handleAction('resume', '1')} 
                  disabled={loading}
                  className="p-2 bg-green-600/20 text-green-500 hover:bg-green-600/40 rounded transition"
                  title="Resume"
                >
                  <Play size={18} />
                </button>
              )}
              {(strategy.status === 1 || strategy.status === 2) && (
                <button 
                  onClick={() => handleAction('cancel', '1')} 
                  disabled={loading}
                  className="p-2 bg-red-600/20 text-red-500 hover:bg-red-600/40 rounded transition"
                  title="Cancel"
                >
                  <XOctagon size={18} />
                </button>
              )}
              {loading && <Loader2 size={18} className="animate-spin text-slate-400 mt-2 ml-2" />}
            </div>
          </div>
          
          <div className="grid grid-cols-2 gap-4 mt-4">
             <div>
                <div className="text-slate-400 text-sm">Target Allocation</div>
                <div className="text-white">{ethers.formatUnits(strategy.targetAllocation, 6)} USDC</div>
             </div>
             <div>
                <div className="text-slate-400 text-sm">Frequency</div>
                <div className="text-white">{Number(strategy.frequency) / 3600} hours</div>
             </div>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
           <p className="text-slate-400 text-sm mb-4">You don't have an active strategy. Create one below.</p>
           
           <div>
              <label className="text-sm text-slate-400 block mb-1">Target Allocation (USDC)</label>
              <input 
                type="number" value={amount} onChange={e => setAmount(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white outline-none"
              />
           </div>
           
           <div>
              <label className="text-sm text-slate-400 block mb-1">Frequency (Seconds)</label>
              <select 
                value={freq} onChange={e => setFreq(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white outline-none"
              >
                <option value="3600">Every Hour</option>
                <option value="86400">Every Day</option>
                <option value="604800">Every Week</option>
              </select>
           </div>
           
           <button 
             onClick={handleCreate} disabled={loading || !provider}
             className="w-full bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white p-2 rounded flex justify-center mt-2"
           >
             {loading ? <Loader2 size={18} className="animate-spin" /> : 'Create Strategy'}
           </button>
        </div>
      )}
    </div>
  );
};
