# Yield-Aware DCA System

A modular, capital-efficient Dollar-Cost Averaging (DCA) protocol on Ethereum. Idle DCA capital generates yield in an ERC-4626 vault while an intelligent execution engine opportunistically times market purchases.

---

## System Architecture

```text
                                  ┌────────────────────────┐
                                  │         USER           │
                                  └───────────┬────────────┘
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      │ 1. Configures Strategy                        │ 2. Deposits USDC
                      ▼                                               ▼
           ┌─────────────────────┐                         ┌─────────────────────┐
           │ Module 1: DCAEngine │                         │ Module 2: YieldVault│
           │ (Strategy Registry) │                         │ (ERC-4626 Capital)  │
           └──────────┬──────────┘                         └──────────┬──────────┘
                      │                                               │
                      │ Strategy Constraints                          │ Vault Balance & APY
                      ▼                                               ▼
           ┌─────────────────────────────────────────────────────────────────────┐
           │                  [Future] Module 5: Decision Engine                 │
           │               (Evaluates: EXECUTE / PARTIAL / DELAY)                │
           └──────────────────────────────────┬──────────────────────────────────┘
                                              │
                                              │ Execution Decision (e.g. 6,000 USDC)
                                              ▼
           ┌─────────────────────────────────────────────────────────────────────┐
           │                 [Future] Module 6: Execution Manager                │
           │                                                                     │
           │  1. Validates bounds against DCAEngine                              │
           │  2. Calls YieldVault.withdrawForStrategy(user, 6000, receiver)      │
           │  3. Receives 6,000 USDC & executes swap on DEX                      │
           └─────────────────────────────────────────────────────────────────────┘
```

---

## Module Roadmap

```text
                ┌────────────────────────┐
                │ Module 1                │
                │ DCA Strategy Management │ ◄── [COMPLETED]
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 2                │
                │ ERC-4626 Yield Vault    │ ◄── [COMPLETED]
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 3                │
                │ Market Analysis        │
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 4                │
                │ Yield Analysis         │
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 5                │
                │ Decision Engine        │
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 6                │
                │ Execution Manager      │
                └───────────┬────────────┘
                            │
                            ▼
                ┌────────────────────────┐
                │ Module 7                │
                │ Uniswap v4 Hook        │
                └────────────────────────┘
```

---

# MODULE 1 — DCA Strategy Management Layer

> *"Module 1 manages DCA strategy configuration and constraints. It does not make market decisions or execute trades."*

### 1. Responsibilities
- **Core Model**: Stores user DCA strategy intent (`targetAllocation`, `frequency`, `maxDelay`, `minExecutionAmount`, `maxExecutionAmount`, `nextExecutionTime`, `status`).
- **State Machine**: Enforces strict lifecycle transitions (`NONE -> ACTIVE`, `ACTIVE <-> PAUSED`, `ACTIVE/PAUSED -> CANCELLED`). Cancelled strategies cannot be resumed or modified.
- **Timing Windows**: Distinguishes 3 temporal states:
  - **BEFORE DUE** (`timestamp < nextExecutionTime`): Execution window not yet open.
  - **EXECUTION WINDOW** (`nextExecutionTime <= timestamp <= nextExecutionTime + maxDelay`): Active execution window.
  - **OVERDUE** (`timestamp > nextExecutionTime + maxDelay`): Allowed delay window has expired.
- **Constraint Checks**: Read-only validation function `isValidExecutionAmount(strategyId, amount)` verifying `minExecutionAmount <= amount <= maxExecutionAmount <= targetAllocation`.

---

# MODULE 2 — ERC-4626 Yield Vault / Capital Management

> *"Module 2 manages deposited capital custody and share accounting. It does not make market decisions or duplicate strategy state."*

### 1. What is ERC-4626 & Why Use It?
ERC-4626 is the standard for tokenized yield-bearing vaults on Ethereum. In standard DCA systems, deposited capital sits completely idle while waiting for recurring execution intervals. In Yield-Aware DCA, capital is held in an ERC-4626 vault (`YieldVault.sol`), continuously earning yield while waiting for the Decision Engine.

### 2. Core Vault Components
- **Underlying Asset**: Configured with a single ERC-20 asset (e.g. `MockERC20` simulating USDC with 6 decimals).
- **Shares**: Pro-rata fractional ownership of all pooled vault assets (`ydcaUSDC`).
- **Standard ERC-4626 API**: `deposit()`, `mint()`, `withdraw()`, `redeem()`, `totalAssets()`, `convertToShares()`, `convertToAssets()`, `preview*()`, `max*()`.
- **Deterministic Mock Yield (`simulateYield`)**:
  - Requires **real underlying tokens** to be transferred from caller to vault via `SafeERC20.safeTransferFrom`.
  - `totalAssets()` increases while `totalSupply()` remains unchanged $\rightarrow$ each share increases in asset value.
  - *Disclaimer*: Mock yield is a deterministic testing/simulation mechanism and does not represent real-world investment returns.
- **Informational APY (`simulatedAPY`)**:
  - Stored in basis points (e.g. `500` = 5.00% APY, bounded by `MAX_APY_BPS = 10_000`).
  - Purely informational for the Decision Engine; setting APY **never** fabricates or mutates vault assets.
- **Controlled Strategy Withdrawal (`withdrawForStrategy`)**:
  - Allows an authorized operator (e.g. Future Module 6 Execution Manager) or owner to withdraw partial execution amounts on behalf of a user strategy.
  - Uses ERC-4626 ceiling rounding (`previewWithdraw(assets)`) to calculate and burn the user's shares.
  - Transfers the exact requested assets directly to `receiver`.

### 3. Capital Flow & Accounting Walkthrough

```text
1. Deposit:
   Alice deposits 10,000 USDC
   Vault: 10,000 USDC assets, 10,000 shares (1 share = 1.00 USDC)
   Alice holds: 10,000 shares (Value: 10,000 USDC)

2. Yield Generation:
   Admin calls simulateYield(100 USDC) with real tokens
   Vault: 10,100 USDC assets, 10,000 shares (1 share ≈ 1.01 USDC)
   Alice holds: 10,000 shares (Value: 10,100 USDC)

3. Partial Strategy Withdrawal:
   Decision Engine selects PARTIAL_EXECUTION = 6,000 USDC
   Execution Manager calls withdrawForStrategy(alice, 6000 USDC, receiver)
   Shares burned: ceil(6000 * 10000 / 10100) = 5,941 shares
   Receiver gets: 6,000 USDC
   Alice remaining shares: 4,059 shares (Value: 4,100 USDC)
   Vault remaining assets: 4,100 USDC
   
   Result: Remaining 4,100 USDC stays in vault earning future yield!
```

### 4. Security & Access Control
- **No Asset Drain Backdoors**: There are no `emergencyWithdraw()`, `sweepTokens()`, or arbitrary asset transfer functions. The owner **cannot** extract depositor funds.
- **Operator Whitelisting**: Only addresses in `isAuthorizedOperator` can execute `withdrawForStrategy`.
- **Ceiling Rounding**: Withdrawals always round shares up in favor of the vault, preventing share manipulation/inflation exploits.

---

# MODULE 3 — Market Data & Market-State Analysis

> *"Module 3 provides a deterministic, replaceable market-data abstraction that produces one normalized `MarketState` object for future decision-engine modules. It does not implement decision logic."*

### 1. Responsibilities
- **Abstract Market Data**: Provides the `IMarketDataProvider` interface to standardise access to market pricing and liquidity conditions.
- **Normalize State**: Computes price deviation, slippage, and price impact via the `MarketAnalyzer` based on the raw data.
- **Deterministic Mocking**: Provides a `MockMarketDataProvider` for deterministic simulation during development and testing of subsequent modules.

### 2. Core Components
- **`MarketDataTypes.sol`**: Contains `RawMarketData` (price, TWAP, volatility, liquidity) and `MarketState` (adds price deviation, estimated slippage, and price impact).
- **`IMarketDataProvider.sol`**: Interface to retrieve raw market snapshot data.
- **`MockMarketDataProvider.sol`**: Deterministic simulated implementation of `IMarketDataProvider`.
- **`MarketAnalyzer.sol`**: Pure-view contract that calculates the `MarketState` (e.g. price impact and slippage derived from volatility/liquidity) for any given trade size.

---

# MODULE 4 — Yield Analysis

> *"Module 4 provides a deterministic, view-only abstraction layer that analyzes the yield characteristics of the deposited capital in the YieldVault. It supplies normalized yield metrics to the future Decision Engine."*

### 1. Responsibilities
- **Abstract Yield Data**: Exposes yield projections decoupled from the low-level `YieldVault` logic via `IYieldAnalyzer`.
- **Normalize State**: Provides a standard `YieldState` indicating current APY, principal assets, and expected absolute yield over 7-day, 30-day, and 365-day horizons.
- **Deterministic Projections**: Calculates standard yield models securely for the future Decision Engine logic (which evaluates yield vs. market opportunities).

### 2. Core Components
- **`YieldDataTypes.sol`**: Contains `YieldState` definition outlining the normalized yield values.
- **`IYieldAnalyzer.sol`**: Interface to retrieve calculated yield metrics.
- **`YieldAnalyzer.sol`**: Stateless, view-only implementation calculating deterministic yield metrics given a specific user or asset principal.

---

## Project Structure

```text
c:\Users\prabu\Downloads\DCA\
├── src/
│   ├── DCAEngine.sol               # [Module 1] Strategy configuration registry
│   ├── YieldVault.sol              # [Module 2] ERC-4626 Yield Vault with mock yield
│   ├── interfaces/
│   │   ├── IDCAStrategy.sol        # [Module 1] Strategy interface
│   │   └── IYieldVault.sol         # [Module 2] Vault interface extending IERC4626
│   ├── libraries/
│   │   └── DCAStrategyLib.sol      # [Module 1] Pure validation & schedule math library
│   └── mocks/
│       └── MockERC20.sol           # [Module 2] Mock USDC test ERC-20 token
├── test/
│   ├── DCAEngine.t.sol             # [Module 1] Engine unit & fuzz tests (31 tests)
│   ├── DCAStrategyLib.t.sol        # [Module 1] Strategy lib tests (9 tests)
│   └── YieldVault.t.sol            # [Module 2] Vault unit, accounting & fuzz tests (29 tests)
├── script/
│   └── DeployDCA.s.sol             # Foundry deployment script (MockUSDC, DCAEngine, YieldVault)
├── foundry.toml                    # Foundry configuration
├── remappings.txt                  # Dependency import remappings
├── .env.example                    # Environment template
├── .gitignore                      # Git ignore rules
└── README.md                       # Comprehensive documentation
```

---

## Build & Testing

### Prerequisites
- [Foundry](https://getfoundry.sh/) (Forge `v1.8.0+`)

### Build
```bash
forge build
```

### Run Tests
```bash
forge test -vvv
```

### Check Coverage
```bash
forge coverage
```

### Format Code
```bash
forge fmt --check
```

---

## Local Deployment (Anvil)

1. Start local Anvil instance:
   ```bash
   anvil
   ```

2. Run the deployment script:
   ```bash
   forge script script/DeployDCA.s.sol:DeployDCA --rpc-url http://127.0.0.1:8545 --broadcast
   ```

Deployed Contracts:
- `MockERC20` (Underlying USDC, 6 decimals)
- `DCAEngine` (Module 1 Strategy Registry)
- `YieldVault` (Module 2 ERC-4626 Yield Vault)
