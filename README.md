# Yield-Aware DCA System

A modular, capital-efficient Dollar-Cost Averaging (DCA) protocol for Ethereum.

## Overview

The Yield-Aware DCA System routes deposited capital into an ERC-4626 yield-bearing vault, earning yield while waiting for the next DCA execution.

Currently implemented modules:
* Module 1 — DCA Strategy Management
* Module 2 — ERC-4626 Yield Vault
* Module 3 — Market Data & Market-State Analysis
* Module 4 — Yield Analysis
* Module 5 — Yield-Aware DCA Decision Engine

## Architecture

```text
Frontend
   ↓
Backend API
   ↓
Contract Services (ethers.js)
   ↓
Ethereum / Anvil (Local Node)
   ↓
Modules 1–5 (Smart Contracts)
```

## Local Development Flow

1. **Start Anvil (Local Blockchain):**
   ```powershell
   anvil
   ```

2. **Deploy Contracts:**
   Open a new terminal and deploy the smart contracts.
   ```powershell
   .\forge.exe script script/DeployDCA.s.sol:DeployDCA --rpc-url http://127.0.0.1:8545 --broadcast
   ```
   Take note of the deployed contract addresses from the output.

3. **Backend Setup:**
   Navigate to the backend directory, copy `.env.example` to `.env`, and populate the contract addresses:
   ```powershell
   cd backend
   npm install
   # Update .env with addresses from step 2
   npm run dev
   ```

4. **Frontend Setup:**
   In a new terminal, navigate to the frontend directory:
   ```powershell
   cd frontend
   npm install
   npm run dev
   ```
   Open `http://localhost:5173` to view the Dashboard. Connect your wallet using the Anvil test network (Chain ID: 31337).

## Application Layer (Modules 1-5 Integration)

### Module 5: Yield-Aware DCA Decision Engine
The Decision Engine orchestrates intelligence from Modules 1-4 to make deterministic DCA execution decisions.

**Core Inputs:**
- DCA Strategy (Module 1)
- Market State (Module 3)
- Yield Analysis (Module 4)
- Current Execution Context (Delay elapsed, Available Capital)

**Outputs (`DecisionResult`):**
- **Action**: `EXECUTE`, `PARTIAL_EXECUTION`, or `DELAY`
- **Execution Amount**: Recommended swap amount
- **Recommended Delay**: Seconds to wait before next evaluation (if delayed)
- **Score**: 0–10000 normalized score indicating the favorability of current conditions
- **Diagnostics**: Traceable record of market, yield, and strategy scores for explainability

**Scoring Model:**
The heuristic model scores three components and weights them using configurable coefficients (default 35% Market, 25% Yield, 40% Strategy).
- **Market Score**: Evaluates price deviation from TWAP, volatility, slippage, liquidity, and price impact.
- **Yield Score**: Evaluates current APY, urgency, and the modeled opportunity cost/benefit of waiting.
- **Strategy Score**: Evaluates time-window urgency and available capital constraints.

If the score crosses `executeThresholdBps` (default 65%), it executes. Between `partialThresholdBps` (default 40%) and execute, it performs a partial execution. Otherwise, it delays unless the maximum delay window is exhausted.

### Frontend (React + Vite + TailwindCSS)
The frontend serves as the primary dashboard to view DCA strategies, vault assets, market analytics, and yield projections. It aggregates these metrics cleanly without modifying contract state directly (except for user wallet interactions like `connect`).

* **Environment configuration:** None strictly required. It connects to the backend API.
* **Commands:**
  * Install: `npm install`
  * Dev: `npm run dev`
  * Build: `npm run build`

### Backend (Node.js + Express)
The backend provides read-only API endpoints to aggregate state from multiple contracts across Modules 1-4. It serves JSON endpoints for the dashboard and persists historical metrics into a lightweight local JSON database.

* **Environment (`backend/.env`):**
  * `PORT=3000`
  * `RPC_URL=http://127.0.0.1:8545`
  * `CHAIN_ID=31337`
  * `DCA_ENGINE_ADDRESS=`
  * `YIELD_VAULT_ADDRESS=`
  * `MARKET_ANALYZER_ADDRESS=`
  * `MOCK_MARKET_PROVIDER_ADDRESS=`
  * `YIELD_ANALYZER_ADDRESS=`
  * `MOCK_ERC20_ADDRESS=`

* **API Endpoints:**
  * `GET /api/health` - Healthcheck
  * `GET /api/dashboard?user=<address>&strategy=<id>` - Aggregated dashboard metrics

* **Commands:**
  * Install: `npm install`
  * Dev: `npm run dev`
  * Build: `npm run build`
  * Test: `npm test`

## Smart Contracts Build & Testing

The contracts use Foundry. All 76 tests currently pass.

```powershell
.\forge.exe build
.\forge.exe test -vvv
.\forge.exe fmt --check
```
