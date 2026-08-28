import React, { useState, useEffect } from 'react';
import { AlertCircle, Play, FastForward, CheckCircle, RefreshCcw } from 'lucide-react';

interface DemoPanelProps {
  strategyId: string;
  onUpdate: () => void;
}

export const DemoPanel: React.FC<DemoPanelProps> = ({ strategyId, onUpdate }) => {
  const [demoStatus, setDemoStatus] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchStatus = async () => {
    try {
      const res = await fetch('/api/demo/status');
      const data = await res.json();
      setDemoStatus(data);
    } catch (e) {
      // Ignore
    }
  };

  useEffect(() => {
    fetchStatus();
    const intv = setInterval(fetchStatus, 3000);
    return () => clearInterval(intv);
  }, []);

  const handleSetup = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/demo/setup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ strategyId })
      });
      if (!res.ok) throw new Error("Failed to setup demo");
      await fetchStatus();
      onUpdate();
    } catch (e: any) {
      setError(e.message);
    }
    setLoading(false);
  };

  const handleStep = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/demo/step', { method: 'POST' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Failed to advance demo");
      await fetchStatus();
      onUpdate();
    } catch (e: any) {
      setError(e.message);
    }
    setLoading(false);
  };

  const handleReset = async () => {
    setLoading(true);
    setError(null);
    try {
      await fetch('/api/demo/reset', { method: 'POST' });
      await fetchStatus();
      onUpdate();
    } catch (e: any) {
      setError(e.message);
    }
    setLoading(false);
  };

  return (
    <div className="bg-slate-800/80 border-2 border-indigo-500/50 rounded-xl p-6 shadow-[0_0_15px_rgba(99,102,241,0.2)] lg:col-span-3 mb-6 relative overflow-hidden">
      {/* Simulation Badge */}
      <div className="absolute top-0 right-0 bg-indigo-600 text-xs font-bold px-3 py-1 rounded-bl-lg tracking-wider text-white">
        TESTNET SIMULATION
      </div>
      
      <div className="flex justify-between items-center mb-6">
        <div>
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">
            🚀 Run DCA Simulation
          </h2>
          <p className="text-slate-400 text-sm mt-1">
            Observe the deterministic behavior over 3 simulated days without real capital execution.
          </p>
        </div>
        
        <div className="flex gap-3">
          {(!demoStatus || demoStatus.state === 'INITIAL') && (
             <button 
               onClick={handleSetup} 
               disabled={loading}
               className="flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded font-medium disabled:opacity-50"
             >
               <Play size={18} /> Initialize Demo
             </button>
          )}
          {demoStatus && demoStatus.state !== 'INITIAL' && demoStatus.state !== 'COMPLETED' && (
             <button 
               onClick={handleStep} 
               disabled={loading}
               className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded font-medium disabled:opacity-50"
             >
               <FastForward size={18} /> Advance Time (1 Day)
             </button>
          )}
          {demoStatus && demoStatus.state !== 'INITIAL' && (
             <button 
               onClick={handleReset} 
               disabled={loading}
               className="flex items-center gap-2 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded font-medium disabled:opacity-50"
             >
               <RefreshCcw size={18} /> Reset Demo
             </button>
          )}
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-900/40 border border-red-500/50 text-red-200 rounded flex items-center gap-2 text-sm">
          <AlertCircle size={16} /> {error}
        </div>
      )}

      {/* Visual Timeline */}
      <div className="grid grid-cols-3 gap-4">
        {/* Day 0 */}
        <div className={`p-4 rounded-lg border ${demoStatus?.simulatedDay >= 0 ? 'bg-slate-700/80 border-slate-500' : 'bg-slate-800/50 border-slate-700 text-slate-500'}`}>
          <div className="font-bold mb-2">Day 0</div>
          <div className="text-sm mb-2">Condition: <span className={demoStatus?.simulatedDay >= 0 ? "text-red-400" : ""}>POOR MARKET</span></div>
          {demoStatus?.simulatedDay >= 0 && (
            <div className="text-sm bg-blue-900/30 text-blue-300 p-2 rounded border border-blue-800">
              <span className="block font-semibold mb-1">Decision: DELAY</span>
              No capital movement. Time advanced.
            </div>
          )}
        </div>

        {/* Day 1 */}
        <div className={`p-4 rounded-lg border ${demoStatus?.simulatedDay >= 1 ? 'bg-slate-700/80 border-slate-500' : 'bg-slate-800/50 border-slate-700 text-slate-500'}`}>
          <div className="font-bold mb-2">Day 1</div>
          <div className="text-sm mb-2">Condition: <span className={demoStatus?.simulatedDay >= 1 ? "text-red-400" : ""}>POOR MARKET</span></div>
          {demoStatus?.simulatedDay >= 1 && (
            <div className="text-sm bg-blue-900/30 text-blue-300 p-2 rounded border border-blue-800">
              <span className="block font-semibold mb-1">Decision: DELAY</span>
              No capital movement. Delay accumulated.
            </div>
          )}
        </div>

        {/* Day 2 */}
        <div className={`p-4 rounded-lg border ${demoStatus?.simulatedDay >= 2 ? 'bg-slate-700/80 border-indigo-500' : 'bg-slate-800/50 border-slate-700 text-slate-500'}`}>
          <div className="font-bold mb-2">Day 2</div>
          <div className="text-sm mb-2">Condition: <span className={demoStatus?.simulatedDay >= 2 ? "text-green-400" : ""}>IMPROVED MARKET</span></div>
          {demoStatus?.simulatedDay >= 2 && (
             <div className="text-sm bg-green-900/30 text-green-300 p-2 rounded border border-green-800">
               <span className="block font-semibold mb-1 flex items-center gap-1"><CheckCircle size={14}/> PARTIAL EXECUTION</span>
               Target: ₹10,000<br/>
               Executed: ₹6,000<br/>
               Remaining: ₹4,000
             </div>
          )}
        </div>
      </div>
    </div>
  );
};
