import React, { useState } from 'react';
import { ethers } from 'ethers';
import { useWallet } from '../hooks/useWallet';
import { executeDecision } from '../services/transactions';
import { BrainCircuit, PlayCircle, Loader2, Calendar, ClipboardList, CheckCircle2, AlertTriangle, Clock } from 'lucide-react';

interface Props {
  strategy: any | null;
  onUpdate: () => void;
}

export const DecisionPanel: React.FC<Props> = ({ strategy, onUpdate }) => {
  const { provider } = useWallet();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [stage, setStage] = useState<string | null>(null);

  if (!strategy) return null;

  const decision = strategy.decision;
  const record = strategy.record;

  const getActionString = (actionVal: number) => {
    // 0 = DELAY, 1 = EXECUTE, 2 = PARTIAL_EXECUTION
    if (actionVal === 1) return 'EXECUTE';
    if (actionVal === 2) return 'PARTIAL EXECUTION';
    return 'DELAY';
  };

  const formatUnits = (val: string | undefined, dec = 6) => {
    if (!val) return '0';
    try {
      return parseFloat(ethers.formatUnits(val, dec)).toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 });
    } catch {
      return "0";
    }
  };

  const handleExecute = async () => {
    if (!provider || !decision) return;
    setLoading(true);
    setError(null);
    setSuccess(null);
    setStage("Preparing...");
    try {
      setStage("Waiting for wallet...");
      await executeDecision(
        provider,
        "1", // strategyId is 1 for MVP
        decision,
        record.nonce.toString(),
        "0" // 0 minimum output for simplicity in MVP simulation
      );
      setStage("Transaction confirmed!");
      setSuccess('Execution successful!');
      onUpdate();
    } catch (err: any) {
      console.error(err);
      setError(err.reason || err.message || 'Execution failed');
    } finally {
      setLoading(false);
      setTimeout(() => setStage(null), 3000);
    }
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6 w-full lg:col-span-3">
      {/* Module 5: Decision Engine recommendation */}
      <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
        <div className="flex justify-between items-center mb-6">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-indigo-500/20 rounded-lg text-indigo-400"><BrainCircuit size={24}/></div>
            <h2 className="text-xl font-semibold">Decision</h2>
          </div>
        </div>

        {error && <div className="mb-4 text-sm text-red-400 p-3 bg-red-900/20 rounded border border-red-500/20">{error}</div>}
        {success && <div className="mb-4 text-sm text-green-400 p-3 bg-green-900/20 rounded border border-green-500/20">{success}</div>}
        {stage && !error && !success && (
          <div className="mb-4 text-sm text-blue-400 p-3 bg-blue-900/20 rounded border border-blue-500/20 flex items-center gap-2">
            <Loader2 size={16} className="animate-spin" /> {stage}
          </div>
        )}

        {decision ? (
          <div className="space-y-6">
            
            {/* Visual Action Indicator */}
            <div className="flex justify-center mb-6">
              <div className={`
                flex items-center gap-2 px-6 py-3 rounded-xl border-2 font-bold tracking-wider
                ${decision.action === 1 ? 'bg-green-500/10 border-green-500 text-green-400 shadow-[0_0_15px_rgba(34,197,94,0.2)]' : ''}
                ${decision.action === 2 ? 'bg-yellow-500/10 border-yellow-500 text-yellow-400 shadow-[0_0_15px_rgba(234,179,8,0.2)]' : ''}
                ${decision.action === 0 ? 'bg-blue-500/10 border-blue-500 text-blue-400 shadow-[0_0_15px_rgba(59,130,246,0.2)]' : ''}
              `}>
                {decision.action === 1 && <CheckCircle2 size={24} />}
                {decision.action === 2 && <AlertTriangle size={24} />}
                {decision.action === 0 && <Clock size={24} />}
                {getActionString(decision.action)}
              </div>
            </div>

            <div className="bg-slate-900/50 rounded-lg p-5 border border-slate-700/50 grid grid-cols-2 gap-y-6 gap-x-4">
              <div>
                <span className="text-slate-400 text-sm block mb-1">Target</span>
                <span className="text-white font-medium text-lg">{formatUnits(decision.targetAmount, 6)} USDC</span>
              </div>
              <div>
                <span className="text-slate-400 text-sm block mb-1">Execute</span>
                <span className="text-white font-medium text-lg">{formatUnits(decision.executionAmount, 6)} USDC</span>
              </div>
              <div>
                <span className="text-slate-400 text-sm block mb-1">Remaining</span>
                <span className="text-white font-medium text-lg">{formatUnits(decision.remainingAmount, 6)} USDC</span>
              </div>
              <div>
                <span className="text-slate-400 text-sm block mb-1">Recommended Delay</span>
                <span className="text-white font-medium text-lg">{Math.round(Number(decision.recommendedDelay)/86400)} day(s)</span>
              </div>
            </div>

            <div>
              <span className="text-slate-400 text-sm block mb-2">Reason</span>
              <p className="text-white text-sm bg-slate-900/40 p-3.5 rounded-lg border border-slate-700/30 leading-relaxed italic">
                {decision.reason || "Determined by on-chain DecisionEngine based on market and yield conditions."}
              </p>
            </div>

            <button
              onClick={handleExecute}
              disabled={loading || !provider}
              className="w-full mt-4 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white rounded-lg py-3 flex justify-center items-center gap-2 transition font-medium shadow-lg shadow-indigo-600/20"
            >
              {loading ? (
                <Loader2 size={20} className="animate-spin" />
              ) : (
                <>
                  <PlayCircle size={20} />
                  Execute Decision
                </>
              )}
            </button>
          </div>
        ) : (
          <div className="py-12 flex flex-col items-center justify-center text-slate-500">
            <Loader2 size={32} className="animate-spin mb-4 text-indigo-500/50" />
            <p className="text-sm">Evaluating strategy decision parameters...</p>
          </div>
        )}
      </div>

      {/* Module 6: Execution Record */}
      <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm">
        <div className="flex items-center gap-3 mb-6">
          <div className="p-2 bg-blue-500/20 rounded-lg text-blue-400"><ClipboardList size={24}/></div>
          <h2 className="text-xl font-semibold">Execution Records (Module 6)</h2>
        </div>

        {record ? (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <span className="text-slate-400 text-sm block">Total Executed</span>
                <span className="text-white font-bold text-lg">{formatUnits(record.totalExecuted, 6)} USDC</span>
              </div>
              <div>
                <span className="text-slate-400 text-sm block">Execution Count</span>
                <span className="text-white font-bold text-lg">{record.executionCount}</span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4 pt-4 border-t border-slate-700/50">
              <div>
                <span className="text-slate-400 text-sm block">Last Execution Amount</span>
                <span className="text-white font-medium">{formatUnits(record.lastExecutionAmount, 6)} USDC</span>
              </div>
              <div>
                <span className="text-slate-400 text-sm block">Next Expected Nonce</span>
                <span className="text-white font-semibold text-indigo-400">{record.nonce}</span>
              </div>
            </div>

            <div className="pt-4 border-t border-slate-700/50 flex justify-between items-center">
              <div>
                <span className="text-slate-400 text-sm block">Last Execution Time</span>
                <span className="text-white text-sm font-medium">
                  {record.lastExecutionTimestamp === "0" 
                    ? "Never Executed" 
                    : new Date(Number(record.lastExecutionTimestamp) * 1000).toLocaleString()}
                </span>
              </div>
              <Calendar size={20} className="text-slate-500" />
            </div>
          </div>
        ) : (
          <div className="py-12 flex flex-col items-center justify-center text-slate-500">
            <ClipboardList size={32} className="mb-4 opacity-50" />
            <p className="text-sm">No execution record found.</p>
          </div>
        )}
      </div>
    </div>
  );
};
