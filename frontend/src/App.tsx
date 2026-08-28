import { WalletProvider } from './hooks/useWallet'
import Dashboard from './pages/Dashboard'

function App() {
  return (
    <WalletProvider>
      <div className="bg-slate-900 min-h-screen text-slate-100 selection:bg-indigo-500/30">
        <Dashboard />
      </div>
    </WalletProvider>
  )
}

export default App
