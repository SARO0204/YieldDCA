import React from 'react';
import { ethers } from 'ethers';

declare global {
  interface Window {
    ethereum?: any;
  }
}

interface WalletContextType {
  address: string | null;
  provider: ethers.BrowserProvider | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  error: string | null;
}

const WalletContext = React.createContext<WalletContextType>({
  address: null,
  provider: null,
  connect: async () => {},
  disconnect: () => {},
  error: null,
});

export const WalletProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [address, setAddress] = React.useState<string | null>(null);
  const [provider, setProvider] = React.useState<ethers.BrowserProvider | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  const connect = async () => {
    try {
      if (!window.ethereum) {
        throw new Error('No crypto wallet found. Please install MetaMask.');
      }
      
      const newProvider = new ethers.BrowserProvider(window.ethereum);
      await newProvider.send('eth_requestAccounts', []);
      const signer = await newProvider.getSigner();
      const addr = await signer.getAddress();
      
      setProvider(newProvider);
      setAddress(addr);
      setError(null);
    } catch (err: any) {
      setError(err.message || 'Failed to connect wallet');
    }
  };

  const disconnect = () => {
    setAddress(null);
    setProvider(null);
  };

  React.useEffect(() => {
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', (accounts: string[]) => {
        if (accounts.length > 0) {
          setAddress(accounts[0]);
        } else {
          disconnect();
        }
      });
    }
  }, []);

  return (
    <WalletContext.Provider value={{ address, provider, connect, disconnect, error }}>
      {children}
    </WalletContext.Provider>
  );
};

export const useWallet = () => React.useContext(WalletContext);
