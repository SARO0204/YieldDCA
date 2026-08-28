import React, { useState } from 'react';
import { ethers } from 'ethers';
import { useWallet } from '../hooks/useWallet';
import { depositVault, withdrawVault } from '../services/transactions';
import { Loader2 } from 'lucide-react';

export const VaultActions: React.FC = () => {
  const { provider, address } = useWallet();
  const [amount, setAmount] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleAction = async (action: 'deposit' | 'withdraw') => {
    if (!provider || !address) return setError('Wallet not connected');
    if (!amount || isNaN(Number(amount))) return setError('Invalid amount');
    
    setLoading(true);
    setError(null);
    setSuccess(null);
    
    try {
      const parsedAmount = ethers.parseUnits(amount, action === 'deposit' ? 6 : 18); // Deposit uses USDC (6), Withdraw uses shares (18)
      
      if (action === 'deposit') {
        await depositVault(provider, parsedAmount.toString(), address);
        setSuccess('Deposit successful!');
      } else {
        await withdrawVault(provider, parsedAmount.toString(), address, address);
        setSuccess('Withdrawal successful!');
      }
      setAmount('');
    } catch (err: any) {
      console.error(err);
      setError(err.reason || err.message || 'Transaction failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="mt-6 p-4 bg-slate-900/50 rounded-lg border border-slate-700">
      <h3 className="text-sm font-semibold text-slate-300 mb-4 uppercase tracking-wider">Manage Capital</h3>
      
      {error && <div className="mb-4 text-sm text-red-400">{error}</div>}
      {success && <div className="mb-4 text-sm text-green-400">{success}</div>}
      
      <div className="flex gap-2 mb-2">
        <input 
          type="number"
          placeholder="Amount"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="flex-1 bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-blue-500"
          disabled={loading}
        />
      </div>
      
      <div className="flex gap-2">
        <button 
          onClick={() => handleAction('deposit')}
          disabled={loading || !provider}
          className="flex-1 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white rounded-lg py-2 flex justify-center items-center gap-2 transition"
        >
          {loading ? <Loader2 size={16} className="animate-spin" /> : 'Deposit'}
        </button>
        <button 
          onClick={() => handleAction('withdraw')}
          disabled={loading || !provider}
          className="flex-1 bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-white rounded-lg py-2 flex justify-center items-center gap-2 transition"
        >
          {loading ? <Loader2 size={16} className="animate-spin" /> : 'Withdraw Shares'}
        </button>
      </div>
    </div>
  );
};
