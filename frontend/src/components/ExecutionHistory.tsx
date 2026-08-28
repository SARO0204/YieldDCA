import React from 'react';
import { History, Clock } from 'lucide-react';
import { ethers } from 'ethers';

interface Props {
  history: any[];
}

export const ExecutionHistory: React.FC<Props> = ({ history }) => {
  const getActionString = (actionVal: number) => {
    const actions = ['DELAY', 'EXECUTE', 'PARTIAL_EXECUTION'];
    return actions[actionVal] || 'UNKNOWN';
  };

  const getActionColor = (actionVal: number) => {
    if (actionVal === 1) return 'text-green-400 border-green-500/20';
    if (actionVal === 2) return 'text-yellow-400 border-yellow-500/20';
    return 'text-blue-400 border-blue-500/20';
  };

  const formatUnits = (val: string | undefined, dec = 6) => {
    if (!val) return '0.0000';
    try {
      return parseFloat(ethers.formatUnits(val, dec)).toFixed(4);
    } catch {
      return "0.0000";
    }
  };

  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 shadow-xl backdrop-blur-sm mt-6">
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2 bg-indigo-500/20 rounded-lg text-indigo-400"><History size={24}/></div>
        <h2 className="text-xl font-semibold">Execution History</h2>
      </div>

      {!history || history.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-8 text-slate-500">
          <Clock size={40} className="mb-2 opacity-50" />
          <p>No executions recorded yet.</p>
        </div>
      ) : (
        <div className="space-y-4 max-h-[400px] overflow-y-auto pr-2 custom-scrollbar">
          {history.map((record, index) => (
            <div key={index} className="bg-slate-900/40 border border-slate-700/50 rounded-lg p-4 transition hover:bg-slate-900/60">
              <div className="flex justify-between items-start mb-2">
                <div className="flex items-center gap-2">
                  <span className="text-slate-400 text-sm font-medium">Execution #{history.length - index}</span>
                  <span className={`px-2 py-0.5 rounded text-[10px] font-bold border bg-slate-900/80 ${getActionColor(record.action)}`}>
                    {getActionString(record.action)}
                  </span>
                </div>
                <div className="text-right">
                  <span className="text-slate-500 text-xs flex items-center gap-1">
                    {new Date(record.timestamp * 1000).toLocaleString()}
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4 mt-3">
                {record.action !== 0 && (
                  <div>
                    <span className="text-slate-500 text-xs block mb-1">Execution Amount</span>
                    <span className="text-white font-medium">{formatUnits(record.requestedAmount, 6)} USDC</span>
                  </div>
                )}
                <div>
                  <span className="text-slate-500 text-xs block mb-1">Status</span>
                  <span className="text-green-400 font-medium text-sm flex items-center gap-1">
                    {record.status || 'Confirmed'}
                  </span>
                </div>
                {record.reason && (
                  <div className="col-span-2 mt-2">
                    <span className="text-slate-500 text-xs block mb-1">Reason</span>
                    <span className="text-slate-300 text-sm italic">"{record.reason}"</span>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
