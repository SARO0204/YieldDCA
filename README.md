# Yield-Aware DCA Prototype

## 1. Problem
Standard Dollar Cost Averaging (DCA) executes trades strictly on a time basis, ignoring market conditions and available yield. This results in users buying during high volatility, suffering high slippage, and missing out on yield while their capital sits idle waiting for the next execution.

## 2. Solution
Yield-Aware DCA introduces a deterministic, mathematically bounded system that analyzes market quality and waiting-opportunity cost to dynamically delay or resize DCA executions. While waiting, user capital earns yield in an ERC-4626 vault.

## 3. Architecture
The system consists of modular smart contracts:
- **DCAEngine**: Strategy registry and state management.
- **YieldVault**: ERC-4626 vault holding user capital.
- **MarketAnalyzer**: Evaluates price deviation, TWAP, volatility, and liquidity.
- **YieldAnalyzer**: Computes opportunity costs versus APY.
- **DecisionEngine**: Pure analytical module calculating deterministic execution scores (EXECUTE, PARTIAL, DELAY).
- **ExecutionManager**: Orchestrates atomic execution, ensuring vault withdrawals and swaps revert together if slippage occurs.
- **DCAExecutionHook**: Uniswap v4 Hook that restricts pool access to authorized DCA executors.

## 4. Modules
This repository contains Modules 1 through 14 of the Yield-Aware DCA system, complete with Solidity contracts, a Node.js API, a React frontend, and a demo orchestrator.

## 5. Technology Stack
- **Smart Contracts**: Solidity (0.8.24), Foundry, OpenZeppelin v5, Uniswap v4 (prerelease).
- **Backend**: Node.js, Express, TypeScript, ethers.js v6.
- **Frontend**: React, Vite, TailwindCSS, ethers.js.

## 6. Decision Algorithm
The Decision Engine computes a composite score based on:
1. **Market Quality**: Penalizes high volatility, high slippage, and poor price deviation from TWAP.
2. **Yield Benefit**: Evaluates if the current APY outweighs the expected opportunity cost of delaying.
3. **Strategy Constraints**: Ensures max delay, minimum executions, and allocation limits are respected.

## 7. ERC-4626 Role
User capital is deposited into `YieldVault`, an ERC-4626 compliant vault. The `ExecutionManager` is granted temporary operator privileges to atomically withdraw only the exact approved execution amount during a DCA cycle.

## 8. Uniswap v4 Hook Role
`DCAExecutionHook` acts as a specialized BeforeSwap hook on a Uniswap v4 pool. It verifies that the `msg.sender` of the swap is an authorized `SwapExecutor`, providing strict execution sandboxing.

## 9. Security Model
- **Non-Custodial**: The backend holds no private keys.
- **Atomicity**: The `ExecutionManager` guarantees that if a swap fails (e.g. slippage), the vault withdrawal reverts.
- **Role-Based Access**: The `YieldVault` restricts withdrawals to authorized operators.

## 10. Local Setup
1. Clone the repository.
2. Run `forge build` and `forge test`.
3. Start Anvil: `anvil`.
4. Deploy contracts (see deployment instructions).
5. Start backend: `cd backend && npm run dev`.
6. Start frontend: `cd frontend && npm run dev`.

## 11. Test Instructions
- Smart Contracts: `forge test -vvv`
- Backend: `cd backend && npm test`

## 12. Demo Instructions
See [docs/DEMO.md](docs/DEMO.md) for full instructions on running the deterministic simulation.

## 13. Known Limitations
- Runs on local Anvil testnet.
- Relies on mock tokens, mock market data, and simulated yield.
- Slippage protection can be bypassed intentionally by authorized callers for testing.
- Uses prerelease Uniswap v4 hook abstractions.

## 14. Future Improvements
- External professional audit.
- Mainnet integration with Gelato for decentralized execution.
- Mainnet Chainlink integration for market data.
